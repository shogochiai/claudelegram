||| Long Polling Loop for Telegram Updates
module Claudelegram.Telegram.LongPoll

import Claudelegram.Telegram.Types
import Claudelegram.Telegram.Api
import Claudelegram.Config
import Claudelegram.Agent
import Data.String
import System

%default covering

||| Poll state
public export
record PollState where
  constructor MkPollState
  lastUpdateId : Integer
  running : Bool
  interactions : List (CorrelationId, InteractionState)

||| Initial poll state
export
initialPollState : PollState
initialPollState = MkPollState 0 True []

||| Handler for incoming updates
public export
UpdateHandler : Type
UpdateHandler = TgUpdate -> IO (Maybe String)

||| Process a single update
processUpdate : Config -> UpdateHandler -> TgUpdate -> IO ()
processUpdate cfg handler update = do
  result <- handler update
  case result of
    Nothing => pure ()
    Just response => do
      _ <- sendTextMessage cfg.botToken cfg.chatId response
      pure ()

||| Poll once for updates
export
pollOnce : Config -> PollState -> UpdateHandler -> IO PollState
pollOnce cfg state handler = do
  let offset = state.lastUpdateId + 1
  result <- getUpdates cfg.botToken offset cfg.pollTimeout

  case result of
    Left err => do
      putStrLn $ "Poll error: \{err}"
      pure state

    Right [] => pure state  -- No updates

    Right updates => do
      -- Process each update
      traverse_ (processUpdate cfg handler) updates
      -- Update offset to highest update_id + 1
      let maxId = foldl max state.lastUpdateId (map updateId updates)
      pure $ { lastUpdateId := maxId } state

||| Run the polling loop (partial - loops forever)
export partial
runPollLoop : Config -> PollState -> UpdateHandler -> IO ()
runPollLoop cfg state handler = do
  newState <- pollOnce cfg state handler
  if newState.running
    then runPollLoop cfg newState handler
    else putStrLn "Polling stopped"

||| Wait for a single response (for one-shot interactions)
||| Returns when a matching response is received or timeout
export
waitForResponse : Config -> CorrelationId -> (timeout : Nat) -> IO (Either String String)
waitForResponse cfg cid timeout = do
  -- Poll with shorter timeout for responsiveness
  let pollTimeout = min timeout 5
  result <- getUpdates cfg.botToken 0 pollTimeout

  case result of
    Left err => pure (Left err)
    Right [] =>
      if timeout <= pollTimeout
        then pure (Left "Timeout waiting for response")
        else waitForResponse cfg cid (minus timeout pollTimeout)
    Right updates =>
      -- Look for a message that matches our CID
      case findMatchingResponse cid updates of
        Just response => pure (Right response)
        Nothing =>
          if timeout <= pollTimeout
            then pure (Left "Timeout")
            else waitForResponse cfg cid (minus timeout pollTimeout)
  where
    findMatchingResponse : CorrelationId -> List TgUpdate -> Maybe String
    findMatchingResponse _ [] = Nothing
    findMatchingResponse cid (MkMessageUpdate _ msg :: rest) =
      case msg.text of
        Just t => Just t  -- Simplified - accept any message
        Nothing => findMatchingResponse cid rest
    findMatchingResponse cid (MkCallbackUpdate _ cb :: rest) =
      cb.callbackData <|> findMatchingResponse cid rest
    findMatchingResponse cid (_ :: rest) = findMatchingResponse cid rest
