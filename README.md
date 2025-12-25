# claudelegram

Human-in-the-Loop Orchestration via Telegram for Local Claude Agents.

An Idris2-based CLI that bridges locally running Claude Code agents with a human operator via Telegram messaging.

## Design Philosophy

- **Human as Interrupt Handler**: Humans are scarce, expensive, non-continuous, and best used reactively
- **Telegram as Human I/O Bus**: Low-friction notification and response channel via long polling
- **Single User Model**: One human, one PC, one smartphone — no multi-tenant complexity

## Security Posture

This system intentionally embraces a **minimalist security posture**:

- Assumes `--dangerously-skip-permissions` execution
- If Telegram account is compromised, the system is effectively rooted
- This is **explicitly accepted**, not mitigated

**Use at your own risk.**

## Requirements

- [Idris2](https://github.com/idris-lang/Idris2) (tested with 0.8.0)
- curl
- tmux (optional, for injection)

## Installation

```bash
git clone git@github.com:shogochiai/claudelegram.git
cd claudelegram
idris2 --build claudelegram.ipkg
```

The executable will be at `./build/exec/claudelegram`.

## Configuration

Set environment variables:

```bash
export TELEGRAM_BOT_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="your-chat-id"

# Optional
export CLAUDELEGRAM_AGENT="claude"           # Agent name for tagging
export CLAUDELEGRAM_TMUX_SESSION="main"      # Default tmux session
export CLAUDELEGRAM_POLL_TIMEOUT="30"        # Poll timeout in seconds
```

## Usage

```bash
# Send notification and wait for response
claudelegram notify "Build failed, please check"

# Send with choice buttons
claudelegram notify "Deploy to production?" -c "yes,no,later"

# Just send a message (no wait)
claudelegram send "Task completed successfully"

# Start long polling daemon
claudelegram poll

# Inject response to tmux session
claudelegram inject mysession "approved"
```

### CLI Options

```
-a, --agent <name>      Agent name for tagging
-t, --tmux <session>    Target tmux session for injection
-f, --fifo <path>       FIFO path for injection
-T, --timeout <secs>    Timeout for waiting
-c, --choices <list>    Comma-separated choices for buttons
```

## Architecture

```
Claude Code (local, parallel)
        │
        │ Notification hook
        ▼
   claudelegram (Idris2)
        │
        │ Telegram Bot API (long polling)
        ▼
     Human (smartphone)
        │
        │ Reply / choice / ESC
        ▼
   claudelegram
        │
        │ tmux send-keys
        ▼
Claude resumes execution
```

## Modules

| Module | Description |
|--------|-------------|
| `Claudelegram.Main` | CLI entry point |
| `Claudelegram.Config` | Environment-based configuration |
| `Claudelegram.Cli` | Command line argument parsing |
| `Claudelegram.Agent` | AgentId and CorrelationId tagging |
| `Claudelegram.Telegram.Types` | Telegram API type definitions |
| `Claudelegram.Telegram.Api` | HTTP API wrapper (sendMessage, getUpdates) |
| `Claudelegram.Telegram.LongPoll` | Long polling loop |
| `Claudelegram.Injection.Tmux` | tmux send-keys injection |
| `Claudelegram.Injection.Fifo` | FIFO-based injection |

## License

MIT
