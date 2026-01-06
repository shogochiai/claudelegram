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
                      -> (transcriptPath : Maybe String)
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

||| Extract project name from transcript path
||| Handles two formats:
||| 1. /Users/bob/code/proj/.claude/sessions/xxx.jsonl -> proj
||| 2. ~/.claude/projects/-Users-bob-code-proj/xxx.jsonl -> proj
extractProjectFromTranscript : String -> String
extractProjectFromTranscript path =
  let parts = forget $ split (== '/') path
  in case findProjectDir parts of
       Just projDir =>
         -- If it looks like encoded path (-Users-bob-code-proj), decode it
         if isPrefixOf "-" projDir
         then let decoded = forget $ split (== '-') projDir
              in fromMaybe "unknown" (last' decoded)
         else projDir
       Nothing => "unknown"
  where
    findProjectDir : List String -> Maybe String
    findProjectDir [] = Nothing
    findProjectDir [_] = Nothing
    findProjectDir [_, _] = Nothing
    findProjectDir (x :: y :: z :: rest) =
      -- Case 1: .claude/projects/<proj-dir>/...
      if x == ".claude" && y == "projects" then Just z
      -- Case 2: <proj>/.claude/... (but not .claude/projects)
      else if y == ".claude" && z /= "projects" then Just x
      else findProjectDir (y :: z :: rest)

||| Decode encoded project path (e.g. -Users-bob-code-proj -> /Users/bob/code/proj)
decodeProjectPath : String -> String
decodeProjectPath s =
  if isPrefixOf "-" s
  then pack $ map (\c => if c == '-' then '/' else c) (unpack s)
  else s

||| Extract project root from transcript path
||| e.g. /Users/bob/code/idris2-ouc/.claude/sessions/xxx.jsonl -> /Users/bob/code/idris2-ouc
||| For ~/.claude/projects/ format, decode the path
extractProjectRoot : String -> Maybe String
extractProjectRoot path =
  let parts = forget $ split (== '/') path
  in findRoot parts
  where
    findRoot : List String -> Maybe String
    findRoot [] = Nothing
    findRoot [_] = Nothing
    findRoot [_, _] = Nothing
    findRoot (x :: y :: z :: rest) =
      -- Case 1: .claude/projects/<encoded-path>/... -> decode path
      if x == ".claude" && y == "projects"
      then Just (decodeProjectPath z)
      -- Case 2: <proj>/.claude/... -> take everything before .claude
      else if y == ".claude" && z /= "projects"
           then Just ("/" ++ joinBy "/" (filter (/= "") (takeWhile (/= ".claude") (x :: y :: z :: rest))))
           else findRoot (y :: z :: rest)

||| Make cwd relative to project root
||| e.g. cwd=/Users/bob/code/idris2-ouc/src, root=/Users/bob/code/idris2-ouc -> src
makeRelativeCwd : String -> String -> String
makeRelativeCwd cwd root =
  let rootLen = length root
      cwdLen = length cwd
  in if isPrefixOf root cwd && cwdLen > rootLen
     then let rel = substr (rootLen + 1) (minus cwdLen (rootLen + 1)) cwd
          in if rel == "" then "." else rel
     else cwd

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
      transcriptPath = extractJsonStringSimple "transcript_path" json
  in Just $ MkNotificationInput notifType message cwd transcriptPath

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
-- Transcript Reading Helpers
-- =============================================================================

||| Take last N elements from a list
takeLast : Nat -> List a -> List a
takeLast n xs = drop (minus (length xs) n) xs

||| Unescape JSON string (convert \n, \t, etc. to actual characters)
unescapeJsonString : String -> String
unescapeJsonString s = pack $ go (unpack s)
  where
    go : List Char -> List Char
    go [] = []
    go ('\\' :: 'n' :: rest) = '\n' :: go rest
    go ('\\' :: 't' :: rest) = '\t' :: go rest
    go ('\\' :: 'r' :: rest) = '\r' :: go rest
    go ('\\' :: '"' :: rest) = '"' :: go rest
    go ('\\' :: '\\' :: rest) = '\\' :: go rest
    go (c :: rest) = c :: go rest

||| Strip XML tags from string (e.g. <status>foo</status> -> foo)
stripXmlTags : String -> String
stripXmlTags s = pack $ go False (unpack s)
  where
    go : Bool -> List Char -> List Char
    go _ [] = []
    go False ('<' :: rest) = go True rest  -- Start skipping tag
    go True ('>' :: rest) = go False rest   -- End skipping tag
    go True (_ :: rest) = go True rest      -- Skip tag content
    go False (c :: rest) = c :: go False rest  -- Keep non-tag content

||| Check if line is an assistant message
isAssistantMessage : String -> Bool
isAssistantMessage line = isInfixOf "\"type\":\"assistant\"" line

||| Extract text from assistant message content array
||| Looks for pattern: "type":"text","text":"..." in the line
extractAssistantText : String -> Maybe String
extractAssistantText line =
  -- Look for "type":"text","text":" pattern
  let chars = unpack line
      pattern = unpack "\"type\":\"text\",\"text\":\""
  in case findPattern pattern chars of
       Nothing => Nothing
       Just idx =>
         let afterPattern = drop (idx + length pattern) chars
             -- Extract until closing quote (handle escaped quotes)
             text = extractUntilQuote afterPattern
         in if null text then Nothing else Just (pack text)
  where
    findPattern : List Char -> List Char -> Maybe Nat
    findPattern needle haystack = go 0 haystack
      where
        startsWith : List Char -> List Char -> Bool
        startsWith [] _ = True
        startsWith _ [] = False
        startsWith (x :: xs) (y :: ys) = x == y && startsWith xs ys

        go : Nat -> List Char -> Maybe Nat
        go _ [] = Nothing
        go n hs@(_ :: rest) =
          if startsWith needle hs then Just n else go (S n) rest

    extractUntilQuote : List Char -> List Char
    extractUntilQuote [] = []
    extractUntilQuote ('\\' :: '"' :: rest) = '\\' :: '"' :: extractUntilQuote rest
    extractUntilQuote ('\\' :: c :: rest) = '\\' :: c :: extractUntilQuote rest
    extractUntilQuote ('"' :: _) = []
    extractUntilQuote (c :: rest) = c :: extractUntilQuote rest

||| Extract text content from a JSONL line
||| For assistant messages: extract message.content[].text where type="text"
||| For other lines: fall back to simple text/content extraction
extractLineContent : String -> Maybe String
extractLineContent line =
  let raw = if isAssistantMessage line
            then extractAssistantText line
            else case extractJsonStringSimple "text" line of
                   Just t => if t == "" then extractJsonStringSimple "content" line else Just t
                   Nothing => extractJsonStringSimple "content" line
  in map (stripXmlTags . unescapeJsonString) raw

||| Read transcript file and extract last N lines of content
||| Returns formatted excerpt of recent Claude output
readTranscriptExcerpt : String -> Nat -> IO String
readTranscriptExcerpt path maxLines = do
  result <- readFile path
  case result of
    Left _ => pure ""
    Right content =>
      let allLines = lines content
          -- Take last N*2 lines (some may not have content)
          recentLines = takeLast (maxLines * 2) allLines
          -- Extract content from each line
          contents = mapMaybe extractLineContent recentLines
          -- Take last maxLines with actual content
          finalContents = takeLast maxLines contents
      in pure $ unlines finalContents

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

execHook cfg (MkNotificationInput notifType msg cwd mTranscriptPath) = do
  let agent = mkAgentId cfg.agentName Nothing
  cidVal <- newCorrelationId cfg.agentName 0
  let tag = formatAgentTag agent cidVal
  let projectName = extractProjectName cwd
  -- For idle_prompt, show [project/cwd] + transcript excerpt
  message <- case (notifType, mTranscriptPath) of
    ("idle_prompt", Just transcriptPath) => do
      excerpt <- readTranscriptExcerpt transcriptPath 15
      let truncatedExcerpt = truncateStr 1500 excerpt
      let projName = extractProjectFromTranscript transcriptPath
      let relCwd = case extractProjectRoot transcriptPath of
                     Just root => makeRelativeCwd cwd root
                     Nothing => cwd
      let header = "[" ++ projName ++ "/" ++ relCwd ++ "]"
      pure $ tag ++ "\n\n" ++ header ++ "\n\n" ++ truncatedExcerpt ++ "\n---"
    _ =>
      let displayMsg = case (notifType, msg == "") of
            ("idle_prompt", True) => "Claude is waiting for your input"
            _ => msg
      in pure $ tag ++ "\n\n" ++ projectName ++ " | " ++ notifType ++ "\n\n" ++ displayMsg
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
