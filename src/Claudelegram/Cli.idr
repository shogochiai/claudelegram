||| CLI Interface
||| Parses command line arguments for the telegram command
module Claudelegram.Cli

import Claudelegram.Config
import Claudelegram.Agent
import Data.String
import Data.List
import Data.List1
import Data.Maybe

%default covering

||| CLI Command types
public export
data Command : Type where
  ||| Send notification and wait for response
  Notify : (reason : String) -> (choices : Maybe (List String)) -> Command
  ||| Send message without waiting
  Send : (message : String) -> Command
  ||| Start long polling daemon
  Poll : Command
  ||| Inject response to tmux/FIFO
  Inject : (target : String) -> (response : String) -> Command
  ||| Show help
  Help : Command
  ||| Show version
  Version : Command

export
Show Command where
  show (Notify reason choices) = "Notify(\{reason}, \{show choices})"
  show (Send msg) = "Send(\{msg})"
  show Poll = "Poll"
  show (Inject target resp) = "Inject(\{target}, \{resp})"
  show Help = "Help"
  show Version = "Version"

||| CLI options
public export
record CliOptions where
  constructor MkCliOptions
  agentName : Maybe String
  tmuxSession : Maybe String
  fifoPath : Maybe String
  timeout : Maybe Nat
  quiet : Bool

||| Default CLI options
export
defaultCliOptions : CliOptions
defaultCliOptions = MkCliOptions Nothing Nothing Nothing Nothing False

||| Parse result
public export
data ParseResult : Type where
  ParseOk : Command -> CliOptions -> ParseResult
  ParseError : String -> ParseResult

||| Parse positive integer as Nat
parseNat : String -> Maybe Nat
parseNat s =
  let trimmed = trim s
  in if all isDigit (unpack trimmed) && trimmed /= ""
     then Just (cast (cast {to=Integer} trimmed))
     else Nothing

||| Parse a single option flag
parseOption : String -> String -> CliOptions -> Either String CliOptions
parseOption "--agent" val opts = Right $ { agentName := Just val } opts
parseOption "-a" val opts = Right $ { agentName := Just val } opts
parseOption "--tmux" val opts = Right $ { tmuxSession := Just val } opts
parseOption "-t" val opts = Right $ { tmuxSession := Just val } opts
parseOption "--fifo" val opts = Right $ { fifoPath := Just val } opts
parseOption "-f" val opts = Right $ { fifoPath := Just val } opts
parseOption "--timeout" val opts =
  case parseNat val of
    Just n => Right $ { timeout := Just n } opts
    Nothing => Left "Invalid timeout value: \{val}"
parseOption "-T" val opts = parseOption "--timeout" val opts
parseOption flag _ _ = Left "Unknown option: \{flag}"

||| Parse choice list from comma-separated string
parseChoices : String -> List String
parseChoices s = filter (/= "") $ map trim $ forget $ split (== ',') s

mutual
  ||| Parse additional options
  parseOpts : List String -> ParseResult -> ParseResult
  parseOpts [] result = result
  parseOpts _ (ParseError e) = ParseError e
  parseOpts (opt :: val :: rest) (ParseOk cmd opts) =
    case parseOption opt val opts of
      Left err => ParseError err
      Right newOpts => parseOpts rest (ParseOk cmd newOpts)
  parseOpts (opt :: []) _ = ParseError "Option \{opt} requires a value"

  ||| Parse notify command
  parseNotify : List String -> CliOptions -> ParseResult
  parseNotify [] _ = ParseError "Missing reason for notify command"
  parseNotify [reason] opts = ParseOk (Notify reason Nothing) opts
  parseNotify (reason :: "--choices" :: choiceStr :: rest) opts =
    parseOpts rest $ ParseOk (Notify reason (Just $ parseChoices choiceStr)) opts
  parseNotify (reason :: "-c" :: choiceStr :: rest) opts =
    parseOpts rest $ ParseOk (Notify reason (Just $ parseChoices choiceStr)) opts
  parseNotify (reason :: rest) opts =
    parseOpts rest $ ParseOk (Notify reason Nothing) opts

  ||| Parse send command
  parseSend : List String -> CliOptions -> ParseResult
  parseSend [] _ = ParseError "Missing message for send command"
  parseSend (msg :: rest) opts = parseOpts rest $ ParseOk (Send msg) opts

  ||| Parse inject command
  parseInject : List String -> CliOptions -> ParseResult
  parseInject [] _ = ParseError "Missing target for inject command"
  parseInject [_] _ = ParseError "Missing response for inject command"
  parseInject (target :: response :: rest) opts =
    parseOpts rest $ ParseOk (Inject target response) opts

||| Parse command line arguments
export
parseArgs : List String -> ParseResult
parseArgs [] = ParseError "No command specified. Use 'telegram --help' for usage."
parseArgs ("--help" :: _) = ParseOk Help defaultCliOptions
parseArgs ("-h" :: _) = ParseOk Help defaultCliOptions
parseArgs ("--version" :: _) = ParseOk Version defaultCliOptions
parseArgs ("-v" :: _) = ParseOk Version defaultCliOptions
parseArgs ("help" :: _) = ParseOk Help defaultCliOptions
parseArgs ("version" :: _) = ParseOk Version defaultCliOptions
parseArgs ("notify" :: rest) = parseNotify rest defaultCliOptions
parseArgs ("send" :: rest) = parseSend rest defaultCliOptions
parseArgs ("poll" :: _) = ParseOk Poll defaultCliOptions
parseArgs ("inject" :: rest) = parseInject rest defaultCliOptions
-- Default: treat first arg as reason for notify
parseArgs (reason :: rest) = parseNotify (reason :: rest) defaultCliOptions

||| Generate help text
export
helpText : String
helpText = """
claudelegram - Human-in-the-Loop Orchestration via Telegram

USAGE:
    claudelegram <command> [options]

COMMANDS:
    notify <reason>     Send notification and wait for response
    send <message>      Send message without waiting
    poll                Start long polling daemon
    inject <target> <response>
                        Inject response to tmux session
    help                Show this help
    version             Show version

OPTIONS:
    -a, --agent <name>      Agent name for tagging
    -t, --tmux <session>    Target tmux session
    -f, --fifo <path>       FIFO path for injection
    -T, --timeout <secs>    Timeout for waiting
    -c, --choices <list>    Comma-separated choices for buttons
    -q, --quiet             Suppress output

ENVIRONMENT:
    TELEGRAM_BOT_TOKEN      Bot token (required)
    TELEGRAM_CHAT_ID        Chat ID (required)
    CLAUDELEGRAM_AGENT      Default agent name
    CLAUDELEGRAM_TMUX_SESSION
                            Default tmux session
    CLAUDELEGRAM_FIFO       Default FIFO path
    CLAUDELEGRAM_POLL_TIMEOUT
                            Default poll timeout

EXAMPLES:
    # Send notification and wait for response
    claudelegram notify "Build failed, please check"

    # Send with choice buttons
    claudelegram notify "Deploy?" -c "yes,no,later"

    # Just send a message
    claudelegram send "Task completed successfully"

    # Start polling daemon
    claudelegram poll

    # Inject response to tmux
    claudelegram inject mysession "approved"
"""

||| Version string
export
versionText : String
versionText = "claudelegram 0.1.0"
