||| Tmux Input Injection
||| Sends keystrokes to tmux sessions
module Claudelegram.Injection.Tmux

import Data.String
import Data.List
import System
import System.File

%default covering

||| Tmux target specification
public export
record TmuxTarget where
  constructor MkTmuxTarget
  session : String
  window : Maybe String
  pane : Maybe String

export
Show TmuxTarget where
  show t = case (t.window, t.pane) of
    (Nothing, Nothing) => t.session
    (Just w, Nothing) => t.session ++ ":" ++ w
    (Nothing, Just p) => t.session ++ ".{" ++ p ++ "}"
    (Just w, Just p) => t.session ++ ":" ++ w ++ "." ++ p

||| Escape special characters for tmux send-keys
escapeForTmux : String -> String
escapeForTmux s = pack $ concatMap escapeChar (unpack s)
  where
    escapeChar : Char -> List Char
    escapeChar ';' = ['\\', ';']
    escapeChar '"' = ['\\', '"']
    escapeChar '$' = ['\\', '$']
    escapeChar '`' = ['\\', '`']
    escapeChar '\\' = ['\\', '\\']
    escapeChar c = [c]

||| Run a shell command
runCmd : String -> IO Int
runCmd cmd = system cmd

||| Build tmux send-keys command
buildSendKeysCmd : TmuxTarget -> String -> Bool -> String
buildSendKeysCmd target text enterAfter =
  let targetArg = "-t '" ++ show target ++ "'"
      enterFlag = if enterAfter then " Enter" else ""
      escapedText = escapeForTmux text
  in "tmux send-keys " ++ targetArg ++ " '" ++ escapedText ++ "'" ++ enterFlag

||| Send text to a tmux session
export
sendKeys : TmuxTarget -> String -> IO (Either String ())
sendKeys target text = do
  let cmd = buildSendKeysCmd target text False
  exitCode <- runCmd cmd
  if exitCode == 0
    then pure (Right ())
    else pure (Left $ "tmux send-keys failed with exit code " ++ show exitCode)

||| Send text followed by Enter
export
sendKeysEnter : TmuxTarget -> String -> IO (Either String ())
sendKeysEnter target text = do
  let cmd = buildSendKeysCmd target text True
  exitCode <- runCmd cmd
  if exitCode == 0
    then pure (Right ())
    else pure (Left $ "tmux send-keys failed with exit code " ++ show exitCode)

||| Send Escape key
export
sendEscape : TmuxTarget -> IO (Either String ())
sendEscape target = do
  let cmd = "tmux send-keys -t '" ++ show target ++ "' Escape"
  exitCode <- runCmd cmd
  if exitCode == 0
    then pure (Right ())
    else pure (Left "tmux send-keys Escape failed")

||| Send Ctrl+C
export
sendCtrlC : TmuxTarget -> IO (Either String ())
sendCtrlC target = do
  let cmd = "tmux send-keys -t '" ++ show target ++ "' C-c"
  exitCode <- runCmd cmd
  if exitCode == 0
    then pure (Right ())
    else pure (Left "tmux send-keys C-c failed")

||| Check if tmux session exists
export
sessionExists : String -> IO Bool
sessionExists session = do
  exitCode <- runCmd $ "tmux has-session -t '" ++ session ++ "' 2>/dev/null"
  pure (exitCode == 0)

||| List available tmux sessions
export
listSessions : IO (Either String (List String))
listSessions = do
  let tmpFile = "/tmp/claudelegram_tmux_sessions.txt"
  let cmd = "tmux list-sessions -F '#{session_name}' > " ++ tmpFile ++ " 2>/dev/null"
  exitCode <- runCmd cmd
  if exitCode /= 0
    then pure (Left "No tmux sessions found")
    else do
      Right content <- readFile tmpFile
        | Left _ => pure (Left "Failed to read sessions")
      pure (Right $ filter (/= "") $ lines content)

||| Create a tmux target from session name
export
mkTarget : String -> TmuxTarget
mkTarget session = MkTmuxTarget session Nothing Nothing

||| Create a tmux target with window
export
mkTargetWindow : String -> String -> TmuxTarget
mkTargetWindow session window = MkTmuxTarget session (Just window) Nothing

||| Create a tmux target with window and pane
export
mkTargetPane : String -> String -> String -> TmuxTarget
mkTargetPane session window pane = MkTmuxTarget session (Just window) (Just pane)
