||| Hook Module
||| Claude Code hook integration - reads stdin, sends Telegram, outputs JSON
module Claudelegram.Hook

import Claudelegram.Config
import Claudelegram.Cli
import Claudelegram.Agent
import Claudelegram.Interaction
import Claudelegram.Telegram.Types
import Claudelegram.Telegram.Api
import Claudelegram.Telegram.JsonParser
import Data.String
import Data.List
import System
import System.File

%default covering

-- =============================================================================
-- Hook Input Parsing (from Claude Code stdin)
-- =============================================================================

||| Parsed hook input from Claude Code
public export
record HookInput where
  constructor MkHookInput
  toolName : String
  toolInput : String

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

||| Parse hook input JSON from stdin
||| Claude Code sends: {"tool_name": "Bash", "tool_input": {"command": "ls -la"}}
parseHookInput : String -> Maybe HookInput
parseHookInput json = do
  toolName <- extractJsonStringSimple "tool_name" json
  -- For tool_input, just include raw json as context (simplified)
  pure $ MkHookInput toolName json

-- =============================================================================
-- Hook Output Generation (to Claude Code stdout)
-- =============================================================================

||| Permission decision for PreToolUse hooks
public export
data PermissionDecision = Allow | Deny | Ask

export
Show PermissionDecision where
  show Allow = "allow"
  show Deny = "deny"
  show Ask = "ask"

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

||| Generate hook output JSON for PreToolUse
||| Format: {"hookSpecificOutput":{"permissionDecision":"allow"}}
generatePreToolOutput : PermissionDecision -> Maybe String -> String
generatePreToolOutput decision mReason =
  let reasonPart = case mReason of
        Nothing => ""
        Just r => ",\"permissionDecisionReason\":\"" ++ escapeJsonString r ++ "\""
  in "{\"hookSpecificOutput\":{\"permissionDecision\":\"" ++ show decision ++ "\"" ++ reasonPart ++ "}}"

||| Generate hook output JSON for PostToolUse (acknowledgment only)
generatePostToolOutput : String
generatePostToolOutput = "{\"hookSpecificOutput\":{}}"

-- =============================================================================
-- Hook Execution
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

||| Format tool info for Telegram message
formatToolMessage : HookEvent -> HookInput -> String
formatToolMessage event input =
  let eventStr = case event of
        PreToolUse => "Tool Request"
        PostToolUse => "Tool Completed"
        Notification => "Notification"
      preview = truncateStr 200 input.toolInput
  in eventStr ++ "\n\nTool: " ++ input.toolName ++ "\n\n```\n" ++ preview ++ "\n```"

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

||| Execute PreToolUse hook
||| Send notification, wait for response, output permission JSON
execPreToolUse : Config -> HookInput -> IO ()
execPreToolUse cfg input = do
  -- Create interaction for one-shot response
  interaction <- mkInteraction cfg (cfg.pollTimeout * 2)
  let cid = getCid interaction
  let agent = mkAgentId cfg.agentName Nothing
  let tag = formatAgentTag agent cid

  -- Format and send message
  let message = tag ++ "\n\n" ++ formatToolMessage PreToolUse input
  let choices = ["Allow", "Deny"]

  result <- sendChoiceMessage cfg.botToken cfg.chatId message choices (show cid)

  case result of
    Left err => do
      -- On error, default to "ask" (let user decide in CLI)
      putStrLn $ generatePreToolOutput Ask (Just ("Telegram error: " ++ err))
    Right _ => do
      -- Wait for response
      responseResult <- await1 interaction cfg

      case responseResult of
        Left err => do
          -- Timeout or error, default to "ask"
          putStrLn $ generatePreToolOutput Ask (Just ("Timeout: " ++ err))
        Right (choice, _) => do
          let decision = choiceToDecision choice
          putStrLn $ generatePreToolOutput decision Nothing

||| Execute PostToolUse hook
||| Send notification only (no response needed)
execPostToolUse : Config -> HookInput -> IO ()
execPostToolUse cfg input = do
  let agent = mkAgentId cfg.agentName Nothing
  cid <- newCorrelationId cfg.agentName 0
  let tag = formatAgentTag agent cid

  let message = tag ++ "\n\n" ++ formatToolMessage PostToolUse input

  _ <- sendTextMessage cfg.botToken cfg.chatId message

  -- Output empty hook response
  putStrLn generatePostToolOutput

||| Execute Notification hook
||| One-way message, no response
execNotification : Config -> HookInput -> IO ()
execNotification cfg input = do
  let agent = mkAgentId cfg.agentName Nothing
  cid <- newCorrelationId cfg.agentName 0
  let tag = formatAgentTag agent cid

  let message = tag ++ "\n\n" ++ formatToolMessage Notification input

  _ <- sendTextMessage cfg.botToken cfg.chatId message

  -- Output empty hook response
  putStrLn generatePostToolOutput

-- =============================================================================
-- Main Hook Entry Point
-- =============================================================================

||| Run hook command
||| Reads tool info from stdin, sends Telegram notification, outputs JSON
export
runHook : Config -> HookEvent -> IO ()
runHook cfg event = do
  -- Read hook input from stdin
  stdinContent <- readStdin

  -- Parse input
  case parseHookInput stdinContent of
    Nothing => do
      -- If we can't parse, just pass through (allow)
      case event of
        PreToolUse => putStrLn $ generatePreToolOutput Allow (Just "Could not parse hook input")
        _ => putStrLn generatePostToolOutput

    Just input => do
      case event of
        PreToolUse => execPreToolUse cfg input
        PostToolUse => execPostToolUse cfg input
        Notification => execNotification cfg input
