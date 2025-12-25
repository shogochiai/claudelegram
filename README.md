# claudelegram

A Telegram CLI for getting human approval from Claude Code.

`notify` → notification on phone → wait for button press → return result → exit.

## Quick Start

```bash
# Build
git clone git@github.com:shogochiai/claudelegram.git
cd claudelegram
idris2 --build claudelegram.ipkg

# Configure
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat-id"

# Use
response=$(claudelegram notify "Deploy?" -c "yes,no")
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

## Documentation

- [User Guide](docs/user-guide.md) - Setup, commands, troubleshooting
- [Contributor Guide](docs/contributor-guide.md) - Architecture, testing, contributing

## License

MIT
