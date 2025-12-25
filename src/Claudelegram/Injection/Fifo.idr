||| FIFO-based Input Injection
||| Alternative injection method using named pipes
module Claudelegram.Injection.Fifo

import Data.String
import System
import System.File

%default covering

||| FIFO configuration
public export
record FifoConfig where
  constructor MkFifoConfig
  path : String
  createIfMissing : Bool

||| Run a shell command
runCmd : String -> IO Int
runCmd cmd = system cmd

||| Check if FIFO exists
export
fifoExists : String -> IO Bool
fifoExists path = do
  exitCode <- runCmd $ "test -p '" ++ path ++ "'"
  pure (exitCode == 0)

||| Create a FIFO (named pipe)
export
createFifo : String -> IO (Either String ())
createFifo path = do
  exitCode <- runCmd $ "mkfifo '" ++ path ++ "' 2>/dev/null"
  if exitCode == 0
    then pure (Right ())
    else do
      -- Check if it already exists as a FIFO
      exists <- fifoExists path
      if exists
        then pure (Right ())
        else pure (Left $ "Failed to create FIFO at " ++ path)

||| Escape for shell
escapeForShell : String -> String
escapeForShell s = pack $ concatMap escape (unpack s)
  where
    escape : Char -> List Char
    escape '"' = ['\\', '"']
    escape '\\' = ['\\', '\\']
    escape '$' = ['\\', '$']
    escape '`' = ['\\', '`']
    escape c = [c]

||| Write to FIFO (non-blocking)
||| Note: This will block if no reader is connected
export
writeToFifo : String -> String -> IO (Either String ())
writeToFifo path content = do
  exists <- fifoExists path
  if not exists
    then pure (Left $ "FIFO does not exist: " ++ path)
    else do
      -- Use timeout to avoid blocking forever
      let cmd = "timeout 1 sh -c 'echo \"" ++ escapeForShell content ++ "\" > \"" ++ path ++ "\"'"
      exitCode <- runCmd cmd
      if exitCode == 0
        then pure (Right ())
        else if exitCode == 124
          then pure (Left "FIFO write timed out (no reader)")
          else pure (Left $ "FIFO write failed with exit code " ++ show exitCode)

||| Write line to FIFO (adds newline)
export
writeLineToFifo : String -> String -> IO (Either String ())
writeLineToFifo path content = writeToFifo path (content ++ "\n")

||| Remove FIFO
export
removeFifo : String -> IO (Either String ())
removeFifo path = do
  exists <- fifoExists path
  if not exists
    then pure (Right ())  -- Already gone
    else do
      exitCode <- runCmd $ "rm '" ++ path ++ "'"
      if exitCode == 0
        then pure (Right ())
        else pure (Left "Failed to remove FIFO")

||| Ensure FIFO exists, creating if configured
export
ensureFifo : FifoConfig -> IO (Either String ())
ensureFifo cfg = do
  exists <- fifoExists cfg.path
  if exists
    then pure (Right ())
    else if cfg.createIfMissing
      then createFifo cfg.path
      else pure (Left $ "FIFO does not exist: " ++ cfg.path)

||| Default FIFO path based on agent name
export
defaultFifoPath : String -> String
defaultFifoPath agentName = "/tmp/claudelegram_" ++ agentName ++ ".fifo"
