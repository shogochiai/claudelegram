||| Hook Module
||| Claude Code hook integration - reads stdin, sends Telegram, outputs JSON
||| Type-safe: each HookEvent has its own input/output types
module Claudelegram.Hook

import Claudelegram.Config
import Claudelegram.Cli
import Claudelegram.Agent
import Claudelegram.Interaction
import Claudelegram.Telegram.Types
import Claudelegram.Telegram.Api
import Claudelegram.Telegram.JsonParser
import Claudelegram.Telegram.LongPoll
import Data.String
import Data.List
import Data.List1
import Data.Maybe
import System
import System.File

%default covering

-- =============================================================================
-- Hook Input Types (type-indexed by HookEvent)
-- =============================================================================

||| Type-indexed hook input - each event has its own structure
public export
data HookInput : HookEvent -> Type where
  ||| PreToolUse input: tool being executed
  MkPreToolUseInput : (toolName : String)
                    -> (toolInput : String)
                    -> (cwd : String)
                    -> (command : Maybe String)
                    -> HookInput PreToolUse
  ||| PostToolUse input: tool that was executed
  MkPostToolUseInput : (toolName : String)
                     -> (toolInput : String)
                     -> (cwd : String)
                     -> HookInput PostToolUse
  ||| Notification input: message and type
  MkNotificationInput : (notificationType : String)
                      -> (message : String)
                      -> (cwd : String)
                      -> HookInput Notification

-- =============================================================================
-- Hook Output Types (type-indexed by HookEvent)
-- =============================================================================

||| Permission decision for PreToolUse hooks
public export
data PermissionDecision = Allow | Deny | Ask

export
Show PermissionDecision where
  show Allow = "allow"
  show Deny = "deny"
  show Ask = "ask"

||| Type-indexed hook output - ensures correct output for each event
public export
data HookOutput : HookEvent -> Type where
  ||| PreToolUse output: permission decision
  MkPreToolUseOutput : PermissionDecision -> Maybe String -> HookOutput PreToolUse
  ||| PostToolUse output: acknowledgment
  MkPostToolUseOutput : HookOutput PostToolUse
  ||| Notification output: optional user response
  MkNotificationOutput : Maybe String -> HookOutput Notification

-- =============================================================================
-- JSON Parsing Helpers
-- =============================================================================

||| Simple JSON string extraction - find value after "key":
||| Just looks for "key":" and extracts until next "
extractJsonStringSimple : String -> String -> Maybe String
extractJsonStringSimple key json =
  let pattern = "\"" ++ key ++ "\":\""
      chars = unpack json
      patternChars = unpack pattern
  in case findSubstring patternChars chars of
       Nothing => Nothing
       Just idx =>
         let afterPattern = drop (idx + length patternChars) chars
             value = takeWhile (/= '"') afterPattern
         in Just (pack value)
  where
    findSubstring : List Char -> List Char -> Maybe Nat
    findSubstring needle haystack = go 0 haystack
      where
        startsWith : List Char -> List Char -> Bool
        startsWith [] _ = True
        startsWith _ [] = False
        startsWith (x :: xs) (y :: ys) = x == y && startsWith xs ys

        go : Nat -> List Char -> Maybe Nat
        go _ [] = Nothing
        go n hs@(_ :: rest) =
          if startsWith needle hs
          then Just n
          else go (S n) rest

||| Extract project name from cwd path (last component)
extractProjectName : String -> String
extractProjectName path =
  let parts = forget $ split (== '/') path
  in case last' parts of
       Just name => if name == "" then "unknown" else name
       Nothing => "unknown"

-- =============================================================================
-- Type-Safe Hook Input Parsing
-- =============================================================================

||| Parse hook input JSON - returns type-indexed input based on event
||| PreToolUse expects tool_name, PostToolUse expects tool_name,
||| Notification expects notification_type and message
export
parseHookInput : (event : HookEvent) -> String -> Maybe (HookInput event)
parseHookInput PreToolUse json = do
  toolName <- extractJsonStringSimple "tool_name" json
  let cwd = fromMaybe "." $ extractJsonStringSimple "cwd" json
  let cmd = extractJsonStringSimple "command" json
  pure $ MkPreToolUseInput toolName json cwd cmd
parseHookInput PostToolUse json = do
  toolName <- extractJsonStringSimple "tool_name" json
  let cwd = fromMaybe "." $ extractJsonStringSimple "cwd" json
  pure $ MkPostToolUseInput toolName json cwd
parseHookInput Notification json =
  let notifType = fromMaybe "unknown" $ extractJsonStringSimple "notification_type" json
      message = fromMaybe "" $ extractJsonStringSimple "message" json
      cwd = fromMaybe "." $ extractJsonStringSimple "cwd" json
  in Just $ MkNotificationInput notifType message cwd

-- =============================================================================
-- Type-Safe Hook Output Serialization
-- =============================================================================

||| Escape JSON string
escapeJsonString : String -> String
escapeJsonString s = pack $ concatMap escape (unpack s)
  where
    escape : Char -> List Char
    escape '"' = ['\\', '"']
    escape '\\' = ['\\', '\\']
    escape '\n' = ['\\', 'n']
    escape '\r' = ['\\', 'r']
    escape '\t' = ['\\', 't']
    escape c = [c]

||| Serialize hook output to JSON - type ensures correct format
export
serializeOutput : HookOutput event -> String
serializeOutput (MkPreToolUseOutput decision mReason) =
  let reasonPart = case mReason of
        Nothing => ""
        Just r => ",\"permissionDecisionReason\":\"" ++ escapeJsonString r ++ "\""
  in "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"" ++ show decision ++ "\"" ++ reasonPart ++ "}}"
serializeOutput MkPostToolUseOutput = "{\"hookSpecificOutput\":{}}"
serializeOutput (MkNotificationOutput Nothing) = "{\"continue\":true}"
serializeOutput (MkNotificationOutput (Just response)) =
  "{\"continue\":true,\"stopReason\":\"" ++ escapeJsonString response ++ "\"}"

-- =============================================================================
-- Hook Execution Helpers
-- =============================================================================

||| Read all stdin
readStdin : IO String
readStdin = do
  result <- fRead stdin
  case result of
    Right content => pure content
    Left _ => pure ""

||| Truncate string to max length
truncateStr : Nat -> String -> String
truncateStr maxLen s =
  let chars = unpack s
  in if length chars > maxLen
     then pack (take maxLen chars) ++ "..."
     else s

||| Map user choice to permission decision
choiceToDecision : String -> PermissionDecision
choiceToDecision choice =
  case toLower (trim choice) of
    "allow" => Allow
    "approve" => Allow
    "yes" => Allow
    "y" => Allow
    "ok" => Allow
    "deny" => Deny
    "reject" => Deny
    "no" => Deny
    "n" => Deny
    _ => Ask

-- =============================================================================
-- Type-Safe Hook Execution
-- =============================================================================

||| Execute hook and return type-indexed output
||| The type system ensures we return the correct output type for each event
export
execHook : Config -> HookInput event -> IO (HookOutput event)
execHook cfg (MkPreToolUseInput toolName toolInput cwd cmd) = do
  -- Create interaction for one-shot response
  interaction <- mkInteraction cfg (cfg.pollTimeout * 2)
  let cidVal = getCid interaction
  let agent = mkAgentId cfg.agentName Nothing
  let tag = formatAgentTag agent cidVal
  let projectName = extractProjectName cwd
  let toolInfo = case cmd of
        Just c => truncateStr 300 c
        Nothing => truncateStr 200 toolInput
  let message = tag ++ "\n\n" ++ projectName ++ " | " ++ toolName ++ "\n\n" ++ toolInfo
  let choices = ["Allow", "Deny"]

  result <- sendChoiceMessage cfg.botToken cfg.chatId message choices (show cidVal)
  case result of
    Left err => pure $ MkPreToolUseOutput Ask (Just ("Telegram error: " ++ err))
    Right _ => do
      responseResult <- await1 interaction cfg
      case responseResult of
        Left err => pure $ MkPreToolUseOutput Ask (Just ("Timeout: " ++ err))
        Right (choice, _) => pure $ MkPreToolUseOutput (choiceToDecision choice) Nothing

execHook cfg (MkPostToolUseInput toolName toolInput cwd) = do
  let agent = mkAgentId cfg.agentName Nothing
  cidVal <- newCorrelationId cfg.agentName 0
  let tag = formatAgentTag agent cidVal
  let projectName = extractProjectName cwd
  let message = tag ++ "\n\n" ++ projectName ++ " | " ++ toolName ++ "\n\n" ++ truncateStr 200 toolInput
  _ <- sendTextMessage cfg.botToken cfg.chatId message
  pure MkPostToolUseOutput

execHook cfg (MkNotificationInput notifType msg cwd) = do
  let agent = mkAgentId cfg.agentName Nothing
  cidVal <- newCorrelationId cfg.agentName 0
  let tag = formatAgentTag agent cidVal
  let projectName = extractProjectName cwd
  -- Use friendly message for known notification types
  let displayMsg = case (notifType, msg == "") of
        ("idle_prompt", True) => "Claude is waiting for your input"
        _ => msg
  let message = tag ++ "\n\n" ++ projectName ++ " | " ++ notifType ++ "\n\n" ++ displayMsg
  result <- sendTextMessage cfg.botToken cfg.chatId message
  case result of
    Left _ => pure $ MkNotificationOutput Nothing
    Right msgId => do
      replyResult <- waitForTextReply cfg msgId (cast cfg.pollTimeout) 0
      case replyResult of
        Left _ => pure $ MkNotificationOutput Nothing
        Right replyText => pure $ MkNotificationOutput (Just replyText)

-- =============================================================================
-- Main Hook Entry Point
-- =============================================================================

||| Run hook command - type-safe dispatch
||| Parses input according to event type, executes, and serializes output
export
runHook : Config -> HookEvent -> IO ()
runHook cfg event = do
  stdinContent <- readStdin
  case event of
    PreToolUse => do
      case parseHookInput PreToolUse stdinContent of
        Nothing => putStrLn $ serializeOutput $ MkPreToolUseOutput Allow (Just "Could not parse hook input")
        Just input => execHook cfg input >>= putStrLn . serializeOutput
    PostToolUse => do
      case parseHookInput PostToolUse stdinContent of
        Nothing => putStrLn $ serializeOutput MkPostToolUseOutput
        Just input => execHook cfg input >>= putStrLn . serializeOutput
    Notification => do
      case parseHookInput Notification stdinContent of
        Nothing => putStrLn $ serializeOutput $ MkNotificationOutput Nothing
        Just input => execHook cfg input >>= putStrLn . serializeOutput
