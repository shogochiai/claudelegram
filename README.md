# claudelegram

A Telegram CLI for getting human approval from Claude Code.

`notify` → notification on phone → wait for button press → return result → exit.

## Usage

```bash
response=$(claudelegram notify "Deploy to production?" -c "yes,no")
# → Notification appears on your phone
# → Waits until you press a button
# → "yes" or "no" is written to stdout
```

## How It Works

```
notify called
    ↓
Send message with buttons to Telegram
    ↓
Human presses button on phone
    ↓
Result written to stdout
    ↓
Process exits
```

**No daemon. One call = one response.**

---

## User Guide

### Setup

#### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) with `/newbot`
2. Save the Bot Token
3. Message your new bot, then get your Chat ID via `https://api.telegram.org/bot<TOKEN>/getUpdates`

#### 2. Build

```bash
git clone git@github.com:shogochiai/claudelegram.git
cd claudelegram
idris2 --build claudelegram.ipkg
```

#### 3. Configure

```bash
export TELEGRAM_BOT_TOKEN="123456:ABC-xyz..."
export TELEGRAM_CHAT_ID="987654321"
```

### Commands

```bash
# Ask for approval (with buttons, waits for response)
claudelegram notify "message" -c "option1,option2,option3"

# Just send a message (no wait)
claudelegram send "message"
```

### Options

```
-c, --choices <list>    Comma-separated choices for buttons
-T, --timeout <secs>    Timeout in seconds
-a, --agent <name>      Agent name (for logging)
```

### Claude Code Integration

In a hook script:

```bash
response=$(claudelegram notify "Run this command? $CMD" -c "yes,no")
if [ "$response" = "yes" ]; then
  eval "$CMD"
fi
```

### Security

- If your Telegram account is compromised, your system is compromised
- Designed for `--dangerously-skip-permissions` execution
- Single user only (no multi-tenant support)

**Use at your own risk.**

---

## Contributor Guide

### Requirements

- [Idris2](https://github.com/idris-lang/Idris2) 0.8.0+
- curl

### Build & Run

```bash
idris2 --build claudelegram.ipkg
./build/exec/claudelegram --help
```

### Project Structure

```
src/
├── Claudelegram/
│   ├── Main.idr              # CLI entry point
│   ├── Config.idr            # Environment-based config
│   ├── Cli.idr               # Argument parsing
│   ├── Agent.idr             # AgentId, CorrelationId
│   ├── Interaction.idr       # One-shot Pending→Completed (linear types)
│   ├── Telegram/
│   │   ├── Types.idr         # Telegram API types
│   │   ├── Api.idr           # HTTP API (sendMessage, getUpdates)
│   │   ├── JsonParser.idr    # Minimal JSON parser
│   │   └── LongPoll.idr      # Polling with CID matching
│   └── Injection/
│       ├── Tmux.idr          # tmux send-keys
│       └── Fifo.idr          # FIFO-based injection
```

### Key Concepts

#### Correlation ID (CID)

Every `notify` generates a unique CID. The CID is embedded in button callbacks as `"CID|CHOICE"`. When polling for responses, only callbacks matching the CID are accepted. This prevents response mix-ups.

#### One-Shot Interaction

The `Interaction` module uses Idris2's linear types:

```idris
await1 : (1 _ : Interaction Pending) -> Config -> IO (Either String (String, Interaction Completed))
```

The `(1 _ : ...)` ensures:
- A `Pending` interaction is consumed exactly once
- Cannot await the same interaction twice
- Cannot discard without awaiting

#### No Daemon

Unlike typical bot architectures, claudelegram doesn't run a persistent daemon. Each `notify` call:
1. Sends a message
2. Polls for the matching callback
3. Returns and exits

This simplifies deployment and avoids state management.

### Testing

Manual test procedure:

1. `claudelegram send "ping"` → verify message arrives
2. `claudelegram notify "test" -c "a,b"` → press button → verify stdout
3. Run two `notify` calls with different CIDs → verify no cross-talk

### Future Work

- [ ] `src/*/SPEC.toml` and `src/*/Tests/` for `lazy core ask` integration
- [ ] Webhook mode (alternative to polling)
- [ ] Response timeout handling improvements

---

## License

MIT
