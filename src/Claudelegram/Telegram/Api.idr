||| Telegram Bot API Client
||| HTTP wrapper for Telegram Bot API calls
module Claudelegram.Telegram.Api

import Claudelegram.Telegram.Types
import Claudelegram.Telegram.JsonParser
import Data.String
import Data.List
import Data.Maybe
import System
import System.File

%default covering

||| API endpoint base URL
baseUrl : String -> String
baseUrl token = "https://api.telegram.org/bot\{token}"

||| Build URL for API method
methodUrl : String -> String -> String
methodUrl token method = "\{baseUrl token}/\{method}"

||| URL encode a string (basic implementation)
export
urlEncode : String -> String
urlEncode s = pack $ concatMap encodeChar (unpack s)
  where
    hexDigit : Int -> Char
    hexDigit n = if n < 10 then chr (ord '0' + n) else chr (ord 'A' + n - 10)

    encodeChar : Char -> List Char
    encodeChar c =
      if isAlphaNum c || c == '-' || c == '_' || c == '.' || c == '~'
        then [c]
        else let n = ord c
             in ['%', hexDigit (n `div` 16), hexDigit (n `mod` 16)]

||| JSON escape a string
export
jsonEscape : String -> String
jsonEscape s = pack $ concatMap escapeChar (unpack s)
  where
    escapeChar : Char -> List Char
    escapeChar '"' = ['\\', '"']
    escapeChar '\\' = ['\\', '\\']
    escapeChar '\n' = ['\\', 'n']
    escapeChar '\r' = ['\\', 'r']
    escapeChar '\t' = ['\\', 't']
    escapeChar c = [c]

||| Build inline keyboard JSON
buildInlineKeyboard : List (List InlineKeyboardButton) -> String
buildInlineKeyboard rows =
  let rowsJson = map buildRow rows
  in "[" ++ joinBy "," rowsJson ++ "]"
  where
    buildButton : InlineKeyboardButton -> String
    buildButton btn =
      let dataField = case btn.callbackData of
            Just d => ",\"callback_data\":\"" ++ jsonEscape d ++ "\""
            Nothing => ""
          urlField = case btn.url of
            Just u => ",\"url\":\"" ++ jsonEscape u ++ "\""
            Nothing => ""
      in "{\"text\":\"" ++ jsonEscape btn.text ++ "\"" ++ dataField ++ urlField ++ "}"

    buildRow : List InlineKeyboardButton -> String
    buildRow btns = "[" ++ joinBy "," (map buildButton btns) ++ "]"

||| Build reply markup JSON
buildReplyMarkup : ReplyMarkup -> String
buildReplyMarkup NoMarkup = ""
buildReplyMarkup (InlineMarkup kb) =
  "{\"inline_keyboard\":" ++ buildInlineKeyboard kb.inlineKeyboard ++ "}"

||| Run a shell command and return exit code
runCmd : String -> IO Int
runCmd cmd = system cmd

||| Send a message via Telegram API
||| Returns message ID on success
export
sendMessage : (token : String) -> SendMessageRequest -> IO (Either String Integer)
sendMessage token req = do
  let url = methodUrl token "sendMessage"
  let parseModeStr = case req.parseMode of
        Just pm => ",\"parse_mode\":\"" ++ pm ++ "\""
        Nothing => ""
  let markupStr = case req.replyMarkup of
        NoMarkup => ""
        m => ",\"reply_markup\":" ++ buildReplyMarkup m
  let body = "{\"chat_id\":" ++ show req.chatId ++ ",\"text\":\"" ++ jsonEscape req.text ++ "\"" ++ parseModeStr ++ markupStr ++ "}"

  putStrLn $ "DEBUG: Sending to " ++ url
  putStrLn $ "DEBUG: Body: " ++ body

  -- Execute curl and capture output via temp file
  let tmpFile = "/tmp/claudelegram_response.json"
  let cmd = "curl -s -X POST '" ++ url ++ "' -H 'Content-Type: application/json' -d '" ++ body ++ "' > " ++ tmpFile
  exitCode <- runCmd cmd
  if exitCode /= 0
    then pure (Left $ "curl failed with exit code " ++ show exitCode)
    else do
      Right content <- readFile tmpFile
        | Left err => pure (Left $ "Failed to read response: " ++ show err)
      -- Check for success
      if isInfixOf "\"ok\":true" content
        then pure (Right 0)  -- Success
        else pure (Left $ "API error: " ++ content)

||| Send a simple text message
export
sendTextMessage : (token : String) -> (chatId : Integer) -> (text : String) -> IO (Either String Integer)
sendTextMessage token chatId text =
  sendMessage token $ MkSendMessageRequest chatId text Nothing NoMarkup

||| Send message with inline keyboard choices
||| Each button's callback_data contains "CID|CHOICE" for correlation
export
sendChoiceMessage : (token : String)
                 -> (chatId : Integer)
                 -> (text : String)
                 -> (choices : List String)
                 -> (cid : String)
                 -> IO (Either String Integer)
sendChoiceMessage token chatId text choices cid =
  let buttons = map (\c => MkInlineKeyboardButton c (Just $ cid ++ "|" ++ c) Nothing) choices
      keyboard = MkInlineKeyboardMarkup [buttons]
      markup = InlineMarkup keyboard
  in sendMessage token $ MkSendMessageRequest chatId text Nothing markup

||| Answer a callback query
export
answerCallbackQuery : (token : String) -> (queryId : String) -> (text : Maybe String) -> IO (Either String ())
answerCallbackQuery token queryId mText = do
  let url = methodUrl token "answerCallbackQuery"
  let textField = case mText of
        Just t => ",\"text\":\"" ++ jsonEscape t ++ "\""
        Nothing => ""
  let body = "{\"callback_query_id\":\"" ++ queryId ++ "\"" ++ textField ++ "}"
  let tmpFile = "/tmp/claudelegram_callback.json"
  let cmd = "curl -s -X POST '" ++ url ++ "' -H 'Content-Type: application/json' -d '" ++ body ++ "' > " ++ tmpFile
  exitCode <- runCmd cmd
  if exitCode /= 0
    then pure (Left "curl failed")
    else pure (Right ())

||| Get updates using long polling
export
getUpdates : (token : String) -> (offset : Integer) -> (timeout : Nat) -> IO (Either String (List TgUpdate))
getUpdates token offset timeout = do
  let url = methodUrl token "getUpdates"
  let body = "{\"offset\":" ++ show offset ++ ",\"timeout\":" ++ show timeout ++ ",\"allowed_updates\":[\"message\",\"callback_query\"]}"
  let tmpFile = "/tmp/claudelegram_updates.json"
  let cmd = "curl -s -X POST '" ++ url ++ "' -H 'Content-Type: application/json' -d '" ++ body ++ "' > " ++ tmpFile

  exitCode <- runCmd cmd
  if exitCode /= 0
    then pure (Left $ "curl failed with exit code " ++ show exitCode)
    else do
      Right content <- readFile tmpFile
        | Left err => pure (Left "Failed to read response")
      -- Parse updates from JSON response
      pure (parseUpdatesJson content)
