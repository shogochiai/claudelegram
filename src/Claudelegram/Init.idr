||| Init Module
||| Interactive setup wizard for Claude Code integration
module Claudelegram.Init

import Claudelegram.Config
import Claudelegram.Cli
import Claudelegram.Telegram.Api
import Data.String
import Data.List
import Data.Maybe
import System
import System.File

%default covering

-- =============================================================================
-- Console Helpers
-- =============================================================================

||| Print with color (ANSI)
printColor : String -> String -> IO ()
printColor color text = putStrLn $ "\ESC[" ++ color ++ "m" ++ text ++ "\ESC[0m"

printGreen : String -> IO ()
printGreen = printColor "32"

printYellow : String -> IO ()
printYellow = printColor "33"

printRed : String -> IO ()
printRed = printColor "31"

printCyan : String -> IO ()
printCyan = printColor "36"

||| Print a header
printHeader : String -> IO ()
printHeader title = do
  putStrLn ""
  printCyan $ "=== " ++ title ++ " ==="
  putStrLn ""

||| Read line from stdin
prompt : String -> IO String
prompt msg = do
  putStr msg
  fflush stdout
  line <- getLine
  pure $ trim line

||| Read line with default value
promptDefault : String -> String -> IO String
promptDefault msg def = do
  putStr $ msg ++ " [" ++ def ++ "]: "
  fflush stdout
  line <- getLine
  let trimmed = trim line
  pure $ if trimmed == "" then def else trimmed

||| Yes/No prompt
promptYN : String -> Bool -> IO Bool
promptYN msg def = do
  let defStr = if def then "Y/n" else "y/N"
  putStr $ msg ++ " [" ++ defStr ++ "]: "
  fflush stdout
  line <- getLine
  let answer = toLower $ trim line
  pure $ case answer of
    "y" => True
    "yes" => True
    "n" => False
    "no" => False
    "" => def
    _ => def

-- =============================================================================
-- Setup Steps
-- =============================================================================

||| Step 1: Telegram Bot Setup Guide
showBotSetupGuide : IO ()
showBotSetupGuide = do
  printHeader "Step 1: Create Telegram Bot"
  putStrLn "1. Open Telegram and search for @BotFather"
  putStrLn "2. Send /newbot command"
  putStrLn "3. Choose a name for your bot (e.g., 'My Claude Assistant')"
  putStrLn "4. Choose a username ending in 'bot' (e.g., 'my_claude_bot')"
  putStrLn "5. BotFather will give you an API token like:"
  printYellow "   123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
  putStrLn ""

||| Step 2: Get Chat ID Guide
showChatIdGuide : IO ()
showChatIdGuide = do
  printHeader "Step 2: Get Your Chat ID"
  putStrLn "1. Open Telegram and find your new bot"
  putStrLn "2. Send /start or any message to the bot"
  putStrLn "3. IMMEDIATELY open this URL (replace TOKEN with your actual token):"
  printYellow "   https://api.telegram.org/bot<TOKEN>/getUpdates"
  putStrLn "4. Look for: \"chat\":{\"id\":123456789}"
  putStrLn ""
  printYellow "   TIP: If result is empty [], send another message and refresh the URL"
  putStrLn ""

||| Step 3: Validate token by sending test message
validateConnection : String -> Integer -> IO Bool
validateConnection token chatId = do
  printHeader "Step 3: Testing Connection"
  putStrLn "Sending test message..."
  result <- sendTextMessage token chatId "🤖 claudelegram connected successfully!"
  case result of
    Right _ => do
      printGreen "✓ Connection successful! Check your Telegram."
      pure True
    Left err => do
      printRed $ "✗ Connection failed: " ++ err
      putStrLn "Please check your token and chat ID."
      pure False

-- =============================================================================
-- Config Generation
-- =============================================================================

||| Generate full settings.local.json content
generateSettingsJson : String
generateSettingsJson =
  "{\n" ++
  "  \"hooks\": {\n" ++
  "    \"PermissionRequest\": [\n" ++
  "      {\n" ++
  "        \"matcher\": \"*\",\n" ++
  "        \"hooks\": [\n" ++
  "          {\n" ++
  "            \"type\": \"command\",\n" ++
  "            \"command\": \"claudelegram hook PreToolUse\"\n" ++
  "          }\n" ++
  "        ]\n" ++
  "      }\n" ++
  "    ],\n" ++
  "    \"Notification\": [\n" ++
  "      {\n" ++
  "        \"matcher\": \"idle_prompt\",\n" ++
  "        \"hooks\": [\n" ++
  "          {\n" ++
  "            \"type\": \"command\",\n" ++
  "            \"command\": \"claudelegram hook Notification\"\n" ++
  "          }\n" ++
  "        ]\n" ++
  "      }\n" ++
  "    ]\n" ++
  "  }\n" ++
  "}\n"

||| Generate shell exports for environment variables
generateEnvExports : String -> Integer -> String
generateEnvExports token chatId =
  "# claudelegram configuration\n" ++
  "export TELEGRAM_BOT_TOKEN=\"" ++ token ++ "\"\n" ++
  "export TELEGRAM_CHAT_ID=\"" ++ show chatId ++ "\"\n"

-- =============================================================================
-- File Operations
-- =============================================================================

||| Ensure directory exists
ensureDir : String -> IO Bool
ensureDir path = do
  result <- system $ "mkdir -p " ++ path
  pure $ result == 0

||| Write settings to .claude/settings.local.json
writeSettings : String -> String -> IO (Either String ())
writeSettings projectPath content = do
  let claudeDir = projectPath ++ "/.claude"
  let settingsPath = claudeDir ++ "/settings.local.json"

  _ <- ensureDir claudeDir

  result <- writeFile settingsPath content
  case result of
    Right () => pure $ Right ()
    Left err => pure $ Left $ "Failed to write settings: " ++ show err

-- =============================================================================
-- Main Init Flow
-- =============================================================================

||| Check for existing env var
getEnvVar : String -> IO (Maybe String)
getEnvVar name = do
  val <- getEnv name
  pure $ case val of
    Just "" => Nothing
    other => other

||| Run the init wizard
export
runInit : IO ()
runInit = do
  printHeader "claudelegram Setup Wizard"
  putStrLn "This wizard will help you set up claudelegram for Claude Code."
  putStrLn ""

  -- Check for existing env vars
  existingToken <- getEnvVar "TELEGRAM_BOT_TOKEN"
  existingChatId <- getEnvVar "TELEGRAM_CHAT_ID"

  -- Get token (use existing automatically, or prompt)
  token <- case existingToken of
    Just t => do
      printGreen "Found TELEGRAM_BOT_TOKEN in environment"
      pure t
    Nothing => do
      showBotSetupGuide
      _ <- prompt "Press Enter when you have your bot token..."
      prompt "Enter your bot token: "

  when (token == "") $ do
    printRed "Token is required. Aborting."
    exitWith (ExitFailure 1)

  -- Get chat ID (use existing automatically, or prompt)
  chatIdStr : String <- case existingChatId of
    Just c => do
      printGreen $ "Found TELEGRAM_CHAT_ID in environment: " ++ c
      pure c
    Nothing => do
      showChatIdGuide
      _ <- prompt "Press Enter when you have your chat ID..."
      prompt "Enter your chat ID: "

  let chatId : Integer = cast chatIdStr
  when (chatId == 0) $ do
    printRed "Invalid chat ID. Aborting."
    exitWith (ExitFailure 1)

  -- Validate connection
  valid <- validateConnection token chatId
  unless valid $ do
    retry <- promptYN "Would you like to re-enter credentials?" True
    unless retry $ exitWith (ExitFailure 1)
    runInit  -- Restart

  -- Generate and write settings (always to current directory)
  printHeader "Generate Configuration"
  let settingsContent = generateSettingsJson

  putStrLn ""
  putStrLn "Generated settings.local.json:"
  printYellow settingsContent

  result <- writeSettings "." settingsContent
  case result of
    Right () => printGreen "✓ Written to .claude/settings.local.json"
    Left err => printRed err

  -- Show env exports only if not already set
  when (isNothing existingToken || isNothing existingChatId) $ do
    printHeader "Environment Variables"
    putStrLn "Add these to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    putStrLn ""
    printYellow $ generateEnvExports token chatId

  -- Done
  printHeader "Setup Complete!"
  when (isNothing existingToken || isNothing existingChatId) $ do
    putStrLn "Next steps:"
    putStrLn "  1. Add the environment variables to your shell"
    putStrLn "  2. Restart your terminal or run: source ~/.bashrc"
    putStrLn "  3. Start Claude Code in this project directory"
    putStrLn ""
  printGreen "This project is now Telegram-enabled!"
