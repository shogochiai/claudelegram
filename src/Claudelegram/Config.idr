||| Configuration Management
||| Loads bot token, chat ID, and agent settings
module Claudelegram.Config

import Data.String
import Data.List
import Data.Maybe
import System
import System.File

%default total

||| Configuration record
public export
record Config where
  constructor MkConfig
  botToken : String
  chatId : Integer
  agentName : String
  tmuxSession : Maybe String
  fifoPath : Maybe String
  pollTimeout : Nat  -- seconds

||| Default configuration values
export
defaultConfig : Config
defaultConfig = MkConfig
  { botToken = ""
  , chatId = 0
  , agentName = "claude"
  , tmuxSession = Nothing
  , fifoPath = Nothing
  , pollTimeout = 30
  }

||| Configuration error
public export
data ConfigError : Type where
  MissingBotToken : ConfigError
  MissingChatId : ConfigError
  InvalidChatId : String -> ConfigError
  FileReadError : String -> ConfigError
  ParseError : String -> ConfigError

export
Show ConfigError where
  show MissingBotToken = "Missing TELEGRAM_BOT_TOKEN environment variable"
  show MissingChatId = "Missing TELEGRAM_CHAT_ID environment variable"
  show (InvalidChatId s) = "Invalid chat ID: \{s}"
  show (FileReadError path) = "Cannot read config file: \{path}"
  show (ParseError msg) = "Config parse error: \{msg}"

||| Parse integer from string
parseInteger : String -> Maybe Integer
parseInteger s =
  let trimmed = trim s
      (neg, digits) = case strUncons trimmed of
        Just ('-', rest) => (True, rest)
        _ => (False, trimmed)
  in if all isDigit (unpack digits) && digits /= ""
     then let val = cast {to=Integer} digits
          in Just (if neg then negate val else val)
     else Nothing

||| Load configuration from environment variables
export
loadConfigFromEnv : IO (Either ConfigError Config)
loadConfigFromEnv = do
  mToken <- getEnv "TELEGRAM_BOT_TOKEN"
  mChatId <- getEnv "TELEGRAM_CHAT_ID"
  mAgent <- getEnv "CLAUDELEGRAM_AGENT"
  mTmux <- getEnv "CLAUDELEGRAM_TMUX_SESSION"
  mFifo <- getEnv "CLAUDELEGRAM_FIFO"
  mTimeout <- getEnv "CLAUDELEGRAM_POLL_TIMEOUT"

  case mToken of
    Nothing => pure (Left MissingBotToken)
    Just "" => pure (Left MissingBotToken)
    Just token => case mChatId of
      Nothing => pure (Left MissingChatId)
      Just "" => pure (Left MissingChatId)
      Just chatIdStr => case parseInteger chatIdStr of
        Nothing => pure (Left (InvalidChatId chatIdStr))
        Just chatId => pure $ Right $ MkConfig
          { botToken = token
          , chatId = chatId
          , agentName = fromMaybe "claude" mAgent
          , tmuxSession = mTmux
          , fifoPath = mFifo
          , pollTimeout = fromMaybe 30 (mTimeout >>= parseNat)
          }
  where
    parseNat : String -> Maybe Nat
    parseNat s = map cast (parseInteger s)

||| Validate configuration
export
validateConfig : Config -> Either ConfigError Config
validateConfig cfg =
  if cfg.botToken == ""
    then Left MissingBotToken
    else if cfg.chatId == 0
      then Left MissingChatId
      else Right cfg
