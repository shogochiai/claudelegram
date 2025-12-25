||| Minimal JSON parser for Telegram API responses
||| Hand-rolled parser to avoid external dependencies
module Claudelegram.Telegram.JsonParser

import Claudelegram.Telegram.Types
import Data.String
import Data.List
import Data.Maybe
import Data.List1

%default covering

||| Skip whitespace
skipWs : List Char -> List Char
skipWs [] = []
skipWs (c :: cs) = if c == ' ' || c == '\n' || c == '\r' || c == '\t'
                     then skipWs cs
                     else c :: cs

||| Parse a JSON string (assumes opening quote consumed)
parseJsonString : List Char -> Maybe (String, List Char)
parseJsonString cs = go [] cs
  where
    go : List Char -> List Char -> Maybe (String, List Char)
    go acc [] = Nothing  -- Unterminated string
    go acc ('"' :: rest) = Just (pack (reverse acc), rest)
    go acc ('\\' :: '"' :: rest) = go ('"' :: acc) rest
    go acc ('\\' :: 'n' :: rest) = go ('\n' :: acc) rest
    go acc ('\\' :: 'r' :: rest) = go ('\r' :: acc) rest
    go acc ('\\' :: 't' :: rest) = go ('\t' :: acc) rest
    go acc ('\\' :: '\\' :: rest) = go ('\\' :: acc) rest
    go acc ('\\' :: c :: rest) = go (c :: acc) rest  -- Other escapes
    go acc (c :: rest) = go (c :: acc) rest

||| Parse a JSON integer
parseJsonInt : List Char -> Maybe (Integer, List Char)
parseJsonInt cs =
  let (neg, cs') = case cs of
        ('-' :: rest) => (True, rest)
        _ => (False, cs)
      (digits, rest) = span isDigit cs'
  in if null digits
       then Nothing
       else let n = cast {to=Integer} (pack digits)
            in Just (if neg then negate n else n, rest)

||| Parse a JSON boolean
parseJsonBool : List Char -> Maybe (Bool, List Char)
parseJsonBool ('t' :: 'r' :: 'u' :: 'e' :: rest) = Just (True, rest)
parseJsonBool ('f' :: 'a' :: 'l' :: 's' :: 'e' :: rest) = Just (False, rest)
parseJsonBool _ = Nothing

-- Skip a JSON value (for fields we don't care about)
mutual
  skipJsonValue : List Char -> Maybe (List Char)
  skipJsonValue [] = Nothing
  skipJsonValue cs@('"' :: _) = map snd (parseJsonString (drop 1 cs))
  skipJsonValue cs@(c :: _) =
    if isDigit c || c == '-'
      then map snd (parseJsonInt cs)
      else if c == 't' || c == 'f'
        then map snd (parseJsonBool cs)
        else if c == 'n'
          then skipNull cs
          else if c == '['
            then skipJsonArray (drop 1 cs)
            else if c == '{'
              then skipJsonObject (drop 1 cs)
              else Nothing

  skipNull : List Char -> Maybe (List Char)
  skipNull ('n' :: 'u' :: 'l' :: 'l' :: rest) = Just rest
  skipNull _ = Nothing

  skipJsonArray : List Char -> Maybe (List Char)
  skipJsonArray cs =
    let cs' = skipWs cs
    in case cs' of
         (']' :: rest) => Just rest
         _ => skipArrayElements cs'

  skipArrayElements : List Char -> Maybe (List Char)
  skipArrayElements cs = do
    rest <- skipJsonValue (skipWs cs)
    let rest' = skipWs rest
    case rest' of
      (']' :: r) => Just r
      (',' :: r) => skipArrayElements (skipWs r)
      _ => Nothing

  skipJsonObject : List Char -> Maybe (List Char)
  skipJsonObject cs =
    let cs' = skipWs cs
    in case cs' of
         ('}' :: rest) => Just rest
         _ => skipObjectFields cs'

  skipObjectFields : List Char -> Maybe (List Char)
  skipObjectFields cs = do
    let cs' = skipWs cs
    case cs' of
      ('"' :: rest) => do
        (_, afterKey) <- parseJsonString rest
        let afterColon = skipWs afterKey
        case afterColon of
          (':' :: valueStart) => do
            afterValue <- skipJsonValue (skipWs valueStart)
            let afterValue' = skipWs afterValue
            case afterValue' of
              ('}' :: r) => Just r
              (',' :: r) => skipObjectFields (skipWs r)
              _ => Nothing
          _ => Nothing
      _ => Nothing

||| Find a string field in a JSON object (starting after '{')
findStringField : String -> List Char -> Maybe String
findStringField fieldName cs = go (skipWs cs)
  where
    go : List Char -> Maybe String
    go [] = Nothing
    go ('}' :: _) = Nothing
    go ('"' :: rest) = do
      (key, afterKey) <- parseJsonString rest
      let afterColon = skipWs afterKey
      case afterColon of
        (':' :: valueStart) =>
          let vs = skipWs valueStart
          in if key == fieldName
               then case vs of
                      ('"' :: vrest) => map fst (parseJsonString vrest)
                      _ => Nothing  -- Not a string value
               else do
                 afterValue <- skipJsonValue vs
                 let afterValue' = skipWs afterValue
                 case afterValue' of
                   (',' :: r) => go (skipWs r)
                   _ => Nothing
        _ => Nothing
    go _ = Nothing

||| Find an integer field in a JSON object
findIntField : String -> List Char -> Maybe Integer
findIntField fieldName cs = go (skipWs cs)
  where
    go : List Char -> Maybe Integer
    go [] = Nothing
    go ('}' :: _) = Nothing
    go ('"' :: rest) = do
      (key, afterKey) <- parseJsonString rest
      let afterColon = skipWs afterKey
      case afterColon of
        (':' :: valueStart) =>
          let vs = skipWs valueStart
          in if key == fieldName
               then map fst (parseJsonInt vs)
               else do
                 afterValue <- skipJsonValue vs
                 let afterValue' = skipWs afterValue
                 case afterValue' of
                   (',' :: r) => go (skipWs r)
                   _ => Nothing
        _ => Nothing
    go _ = Nothing

||| Find a boolean field in a JSON object
findBoolField : String -> List Char -> Maybe Bool
findBoolField fieldName cs = go (skipWs cs)
  where
    go : List Char -> Maybe Bool
    go [] = Nothing
    go ('}' :: _) = Nothing
    go ('"' :: rest) = do
      (key, afterKey) <- parseJsonString rest
      let afterColon = skipWs afterKey
      case afterColon of
        (':' :: valueStart) =>
          let vs = skipWs valueStart
          in if key == fieldName
               then map fst (parseJsonBool vs)
               else do
                 afterValue <- skipJsonValue vs
                 let afterValue' = skipWs afterValue
                 case afterValue' of
                   (',' :: r) => go (skipWs r)
                   _ => Nothing
        _ => Nothing
    go _ = Nothing

||| Find a nested object field and return its contents (as char list after '{')
findObjectField : String -> List Char -> Maybe (List Char)
findObjectField fieldName cs = go (skipWs cs)
  where
    go : List Char -> Maybe (List Char)
    go [] = Nothing
    go ('}' :: _) = Nothing
    go ('"' :: rest) = do
      (key, afterKey) <- parseJsonString rest
      let afterColon = skipWs afterKey
      case afterColon of
        (':' :: valueStart) =>
          let vs = skipWs valueStart
          in if key == fieldName
               then case vs of
                      ('{' :: objRest) => Just objRest
                      _ => Nothing
               else do
                 afterValue <- skipJsonValue vs
                 let afterValue' = skipWs afterValue
                 case afterValue' of
                   (',' :: r) => go (skipWs r)
                   _ => Nothing
        _ => Nothing
    go _ = Nothing

||| Parse a TgUser from object contents
parseTgUser : List Char -> Maybe TgUser
parseTgUser cs = do
  id <- findIntField "id" cs
  isBot <- findBoolField "is_bot" cs <|> Just False
  firstName <- findStringField "first_name" cs <|> Just "Unknown"
  let lastName = findStringField "last_name" cs
  let username = findStringField "username" cs
  pure $ MkTgUser id isBot firstName lastName username

||| Parse a TgChat from object contents
parseTgChat : List Char -> Maybe TgChat
parseTgChat cs = do
  id <- findIntField "id" cs
  chatType <- findStringField "type" cs <|> Just "private"
  let title = findStringField "title" cs
  let username = findStringField "username" cs
  pure $ MkTgChat id chatType title username

||| Parse a TgMessage from object contents
parseTgMessage : List Char -> Maybe TgMessage
parseTgMessage cs = do
  messageId <- findIntField "message_id" cs
  date <- findIntField "date" cs <|> Just 0
  chatObj <- findObjectField "chat" cs
  chat <- parseTgChat chatObj
  let mFrom = do
        fromObj <- findObjectField "from" cs
        parseTgUser fromObj
  let text = findStringField "text" cs
  pure $ MkTgMessage messageId mFrom chat date text Nothing

||| Parse a TgCallbackQuery from object contents
parseTgCallbackQuery : List Char -> Maybe TgCallbackQuery
parseTgCallbackQuery cs = do
  id <- findStringField "id" cs
  fromObj <- findObjectField "from" cs
  from <- parseTgUser fromObj
  chatInstance <- findStringField "chat_instance" cs <|> Just ""
  let callbackData = findStringField "data" cs
  let mMessage = do
        msgObj <- findObjectField "message" cs
        parseTgMessage msgObj
  pure $ MkTgCallbackQuery id from mMessage chatInstance callbackData

||| Parse a single update object
parseUpdate : List Char -> Maybe TgUpdate
parseUpdate cs = do
  updateId <- findIntField "update_id" cs
  -- Try callback_query first, then message
  let mCallback = do
        cbObj <- findObjectField "callback_query" cs
        cb <- parseTgCallbackQuery cbObj
        pure $ MkCallbackUpdate updateId cb
  let mMessage = do
        msgObj <- findObjectField "message" cs
        msg <- parseTgMessage msgObj
        pure $ MkMessageUpdate updateId msg
  mCallback <|> mMessage <|> Just (MkUnknownUpdate updateId)

||| Find the "result" array and parse each update
parseResultArray : List Char -> List TgUpdate
parseResultArray cs = go (skipWs cs) []
  where
    parseOneUpdate : List Char -> Maybe (TgUpdate, List Char)
    parseOneUpdate cs' =
      let cs'' = skipWs cs'
      in case cs'' of
           ('{' :: rest) => do
             update <- parseUpdate rest
             afterObj <- skipJsonObject rest
             pure (update, afterObj)
           _ => Nothing

    go : List Char -> List TgUpdate -> List TgUpdate
    go [] acc = reverse acc
    go (']' :: _) acc = reverse acc
    go cs' acc =
      case parseOneUpdate cs' of
        Nothing => reverse acc
        Just (update, rest) =>
          let rest' = skipWs rest
          in case rest' of
               (',' :: r) => go (skipWs r) (update :: acc)
               _ => reverse (update :: acc)

||| Parse the full getUpdates response
||| Expected format: {"ok":true,"result":[...]}
export
parseUpdatesJson : String -> Either String (List TgUpdate)
parseUpdatesJson json =
  let cs = unpack json
      cs' = skipWs cs
  in case cs' of
       ('{' :: rest) =>
         -- Check for "ok":true
         case findBoolField "ok" rest of
           Just True =>
             -- Find "result" array
             case findResultArray rest of
               Just arrayContents => Right (parseResultArray arrayContents)
               Nothing => Right []  -- No result array, treat as empty
           Just False =>
             let desc = fromMaybe "Unknown error" (findStringField "description" rest)
             in Left desc
           Nothing => Left "Missing 'ok' field in response"
       _ => Left "Invalid JSON: expected object"
  where
    -- Find the "result" array and return contents after '['
    findResultArray : List Char -> Maybe (List Char)
    findResultArray cs = go (skipWs cs)
      where
        go : List Char -> Maybe (List Char)
        go [] = Nothing
        go ('}' :: _) = Nothing
        go ('"' :: rest) = do
          (key, afterKey) <- parseJsonString rest
          let afterColon = skipWs afterKey
          case afterColon of
            (':' :: valueStart) =>
              let vs = skipWs valueStart
              in if key == "result"
                   then case vs of
                          ('[' :: arrRest) => Just arrRest
                          _ => Nothing
                   else do
                     afterValue <- skipJsonValue vs
                     let afterValue' = skipWs afterValue
                     case afterValue' of
                       (',' :: r) => go (skipWs r)
                       _ => Nothing
            _ => Nothing
        go _ = Nothing

||| Parse callback_data in format "CID|CHOICE"
export
parseCallbackData : String -> Maybe (String, String)
parseCallbackData s =
  let parts = forget $ split (== '|') s
  in case parts of
       [cid, choice] => Just (cid, choice)
       _ => Nothing
