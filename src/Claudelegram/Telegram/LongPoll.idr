||| Long Polling Loop for Telegram Updates
module Claudelegram.Telegram.LongPoll

import Claudelegram.Telegram.Types
import Claudelegram.Telegram.Api
import Claudelegram.Telegram.JsonParser
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
||| Only accepts CallbackQuery with matching CID in callback_data
export
waitForResponse : Config -> CorrelationId -> (timeout : Nat) -> (offset : Integer) -> IO (Either String String)
waitForResponse cfg cid timeout offset = do
  -- Poll with shorter timeout for responsiveness
  let pollTimeout = min timeout 5
  result <- getUpdates cfg.botToken offset pollTimeout

  case result of
    Left err => pure (Left err)
    Right [] =>
      if timeout <= pollTimeout
        then pure (Left "Timeout waiting for response")
        else waitForResponse cfg cid (minus timeout pollTimeout) offset
    Right updates =>
      -- Calculate next offset to avoid re-reading same updates
      let maxId = foldl max offset (map updateId updates)
          nextOffset = maxId + 1
      in
      -- Look for a callback that matches our CID
      case findMatchingResponse cid updates of
        Just response => pure (Right response)
        Nothing =>
          if timeout <= pollTimeout
            then pure (Left "Timeout")
            else waitForResponse cfg cid (minus timeout pollTimeout) nextOffset
  where
    ||| Find a callback response matching the given CID
    ||| Only considers CallbackQuery updates with "CID|CHOICE" format
    findMatchingResponse : CorrelationId -> List TgUpdate -> Maybe String
    findMatchingResponse _ [] = Nothing
    -- Ignore message updates (text replies not supported in callback mode)
    findMatchingResponse targetCid (MkMessageUpdate _ _ :: rest) =
      findMatchingResponse targetCid rest
    -- Check callback updates for CID match
    findMatchingResponse targetCid (MkCallbackUpdate _ cb :: rest) =
      case cb.callbackData of
        Nothing => findMatchingResponse targetCid rest
        Just data_ =>
          case parseCallbackData data_ of
            Nothing => findMatchingResponse targetCid rest
            Just (cidStr, choice) =>
              if cidStr == show targetCid
                then Just choice
                else findMatchingResponse targetCid rest
    findMatchingResponse targetCid (_ :: rest) = findMatchingResponse targetCid rest

||| Wait for a text reply to a specific message (for idle_prompt etc.)
||| Returns when a reply to sentMsgId is received or timeout
||| Matches by reply_to_message.message_id
export
waitForTextReply : Config -> (sentMsgId : Integer) -> (timeout : Nat) -> (offset : Integer) -> IO (Either String String)
waitForTextReply cfg sentMsgId timeout offset = do
  let pollTimeout = min timeout 5
  result <- getUpdates cfg.botToken offset pollTimeout

  case result of
    Left err => pure (Left err)
    Right [] =>
      if timeout <= pollTimeout
        then pure (Left "Timeout waiting for text reply")
        else waitForTextReply cfg sentMsgId (minus timeout pollTimeout) offset
    Right updates =>
      let maxId = foldl max offset (map updateId updates)
          nextOffset = maxId + 1
      in
      case findMatchingReply sentMsgId updates of
        Just response => pure (Right response)
        Nothing =>
          if timeout <= pollTimeout
            then pure (Left "Timeout")
            else waitForTextReply cfg sentMsgId (minus timeout pollTimeout) nextOffset
  where
    ||| Find a text message that replies to our sent message
    findMatchingReply : Integer -> List TgUpdate -> Maybe String
    findMatchingReply _ [] = Nothing
    findMatchingReply targetMsgId (MkMessageUpdate _ msg :: rest) =
      case (msg.text, msg.replyToMessageId) of
        (Just txt, Just replyId) =>
          if replyId == targetMsgId
            then Just txt
            else findMatchingReply targetMsgId rest
        _ => findMatchingReply targetMsgId rest
    findMatchingReply targetMsgId (_ :: rest) = findMatchingReply targetMsgId rest
