||| Telegram Bot API Types
||| Based on https://core.telegram.org/bots/api
module Claudelegram.Telegram.Types

import Data.List
import Data.String
import Data.Maybe

%default total

||| Telegram User
public export
record TgUser where
  constructor MkTgUser
  id : Integer
  isBot : Bool
  firstName : String
  lastName : Maybe String
  username : Maybe String

||| Telegram Chat
public export
record TgChat where
  constructor MkTgChat
  id : Integer
  chatType : String  -- "private", "group", "supergroup", "channel"
  title : Maybe String
  username : Maybe String

||| Telegram Message
public export
record TgMessage where
  constructor MkTgMessage
  messageId : Integer
  from : Maybe TgUser
  chat : TgChat
  date : Integer
  text : Maybe String
  replyToMessage : Maybe (Lazy TgMessage)

||| Callback Query (for inline keyboard buttons)
public export
record TgCallbackQuery where
  constructor MkTgCallbackQuery
  id : String
  from : TgUser
  message : Maybe TgMessage
  chatInstance : String
  callbackData : Maybe String

||| Update object from getUpdates
public export
data TgUpdate : Type where
  MkMessageUpdate : (updateId : Integer) -> (message : TgMessage) -> TgUpdate
  MkCallbackUpdate : (updateId : Integer) -> (callback : TgCallbackQuery) -> TgUpdate
  MkUnknownUpdate : (updateId : Integer) -> TgUpdate

||| Extract update ID
public export
updateId : TgUpdate -> Integer
updateId (MkMessageUpdate uid _) = uid
updateId (MkCallbackUpdate uid _) = uid
updateId (MkUnknownUpdate uid) = uid

||| Inline keyboard button
public export
record InlineKeyboardButton where
  constructor MkInlineKeyboardButton
  text : String
  callbackData : Maybe String
  url : Maybe String

||| Inline keyboard markup
public export
record InlineKeyboardMarkup where
  constructor MkInlineKeyboardMarkup
  inlineKeyboard : List (List InlineKeyboardButton)

||| Reply markup union type
public export
data ReplyMarkup : Type where
  InlineMarkup : InlineKeyboardMarkup -> ReplyMarkup
  NoMarkup : ReplyMarkup

||| Send message request
public export
record SendMessageRequest where
  constructor MkSendMessageRequest
  chatId : Integer
  text : String
  parseMode : Maybe String
  replyMarkup : ReplyMarkup

||| API Response wrapper
public export
data ApiResponse : Type -> Type where
  ApiOk : (result : a) -> ApiResponse a
  ApiError : (errorCode : Int) -> (description : String) -> ApiResponse a

||| Show instance for debugging
export
Show TgUser where
  show u = "User(\{show u.id}, \{u.firstName})"

export
Show TgChat where
  show c = "Chat(\{show c.id}, \{c.chatType})"

export
Show TgMessage where
  show m = let txt = fromMaybe "" m.text in "Message(\{show m.messageId}, \{txt})"

export
Show TgUpdate where
  show (MkMessageUpdate uid msg) = "Update(\{show uid}, \{show msg})"
  show (MkCallbackUpdate uid cb) = "CallbackUpdate(\{show uid}, \{cb.id})"
  show (MkUnknownUpdate uid) = "UnknownUpdate(\{show uid})"
