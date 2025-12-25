||| Main Entry Point
||| claudelegram CLI application
module Claudelegram.Main

import Claudelegram.Config
import Claudelegram.Cli
import Claudelegram.Agent
import Claudelegram.Interaction
import Claudelegram.Telegram.Types
import Claudelegram.Telegram.Api
import Claudelegram.Telegram.LongPoll
import Claudelegram.Injection.Tmux
import Claudelegram.Injection.Fifo

import Data.String
import Data.List
import Data.Maybe
import System

%default covering

||| Merge CLI options with config
mergeOptions : Config -> CliOptions -> Config
mergeOptions cfg opts =
  { agentName := fromMaybe cfg.agentName opts.agentName
  , tmuxSession := opts.tmuxSession <|> cfg.tmuxSession
  , fifoPath := opts.fifoPath <|> cfg.fifoPath
  , pollTimeout := fromMaybe cfg.pollTimeout opts.timeout
  } cfg

||| Execute notify command (one-shot interaction)
||| Sends message with choices, waits for callback response matching CID
execNotify : Config -> String -> Maybe (List String) -> IO ()
execNotify cfg reason mChoices = do
  -- Create one-shot interaction (generates CID)
  interaction <- mkInteraction cfg (cfg.pollTimeout * 2)
  let cid = getCid interaction
  let agent = mkAgentId cfg.agentName Nothing
  let tag = formatAgentTag agent cid

  -- Format message
  let message = "\{tag}\n\n\{reason}"

  -- Send message (with or without choices)
  -- Note: Without choices, we send but don't wait (one-way message)
  result <- the (IO (Either String Integer)) $ case mChoices of
    Nothing => sendTextMessage cfg.botToken cfg.chatId message
    Just choices => sendChoiceMessage cfg.botToken cfg.chatId message choices (show cid)

  case result of
    Left err => do
      putStrLn $ "Error sending message: \{err}"
      exitWith (ExitFailure 1)
    Right _ => do
      putStrLn $ "Notification sent: \{show cid}"

      -- Only wait for response if choices were provided
      case mChoices of
        Nothing => do
          putStrLn "One-way message sent (no choices, not waiting)"
          pure ()
        Just _ => do
          -- Wait for response using one-shot interaction
          putStrLn "Waiting for response..."
          responseResult <- await1 interaction cfg

          case responseResult of
            Left err => do
              putStrLn $ "Error waiting for response: \{err}"
              exitWith (ExitFailure 1)
            Right (resp, _) => do
              -- Output response to stdout (caller can capture this)
              putStrLn resp

||| Execute send command
execSend : Config -> String -> IO ()
execSend cfg message = do
  cid <- newCorrelationId cfg.agentName 0
  let agent = mkAgentId cfg.agentName Nothing
  let tag = formatAgentTag agent cid
  let fullMessage = "\{tag}\n\n\{message}"

  result <- sendTextMessage cfg.botToken cfg.chatId fullMessage
  case result of
    Left err => do
      putStrLn $ "Error: \{err}"
      exitWith (ExitFailure 1)
    Right _ => putStrLn "Message sent"

||| Execute poll command
execPoll : Config -> IO ()
execPoll cfg = do
  putStrLn $ "Starting long polling for agent: \{cfg.agentName}"
  putStrLn $ "Chat ID: \{show cfg.chatId}"
  putStrLn $ "Poll timeout: \{show cfg.pollTimeout}s"
  putStrLn "Press Ctrl+C to stop"

  let handler : UpdateHandler = \update => do
        putStrLn $ "Received: \{show update}"
        case update of
          MkMessageUpdate _ msg => do
            case msg.text of
              Just "/ping" => pure $ Just "pong"
              Just "/status" => pure $ Just "Agent \{cfg.agentName} is running"
              _ => pure Nothing
          MkCallbackUpdate _ cb => do
            _ <- answerCallbackQuery cfg.botToken cb.id (Just "Acknowledged")
            case cb.callbackData of
              Just data_ => do
                putStrLn $ "Callback: \{data_}"
                -- Inject to tmux if configured
                case cfg.tmuxSession of
                  Nothing => pure ()
                  Just session => do
                    let target = mkTarget session
                    _ <- sendKeysEnter target data_
                    pure ()
                pure Nothing
              Nothing => pure Nothing
          _ => pure Nothing

  runPollLoop cfg initialPollState handler

||| Execute inject command
execInject : Config -> String -> String -> IO ()
execInject cfg target response = do
  let tmuxTarget = mkTarget target
  result <- sendKeysEnter tmuxTarget response
  case result of
    Left err => do
      putStrLn $ "Error: \{err}"
      exitWith (ExitFailure 1)
    Right () => putStrLn $ "Injected '\{response}' to \{target}"

||| Main entry point
main : IO ()
main = do
  args <- getArgs

  -- Skip program name
  let cmdArgs = drop 1 args

  case parseArgs cmdArgs of
    ParseError err => do
      putStrLn $ "Error: \{err}"
      putStrLn "Use 'claudelegram --help' for usage information"
      exitWith (ExitFailure 1)

    ParseOk Help _ => putStrLn helpText

    ParseOk Version _ => putStrLn versionText

    ParseOk cmd opts => do
      -- Load config from environment
      configResult <- loadConfigFromEnv

      case configResult of
        Left err => do
          putStrLn $ "Configuration error: \{show err}"
          exitWith (ExitFailure 1)

        Right cfg => do
          let finalCfg = mergeOptions cfg opts

          case cmd of
            Notify reason choices => execNotify finalCfg reason choices
            Send message => execSend finalCfg message
            Poll => execPoll finalCfg
            Inject target response => execInject finalCfg target response
            Help => putStrLn helpText
            Version => putStrLn versionText
