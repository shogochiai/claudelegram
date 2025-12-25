# claudelegram

Human-in-the-loop orchestration via Telegram for Claude Code.

When Claude wants to run a command, you get a Telegram notification with Allow/Deny buttons.

## Quick Start

```bash
# Build and install
git clone https://github.com/user/claudelegram
cd claudelegram
sudo make install

# In your project directory
claudelegram init
```

First-time users: `init` guides you through creating a Telegram bot and getting your chat ID.

Returning users (env vars already set): `claudelegram init` instantly enables the project.

## How It Works

**Permission Requests:**
```
Claude wants to run `rm -rf /tmp/test`
    ↓
You get Telegram: [Allow] [Deny]
    ↓
You tap Allow → Claude proceeds
```

**Idle Prompt (Claude waiting for input):**
```
Claude finishes a task and waits
    ↓
You get Telegram: "Claude is waiting for your input"
    ↓
You reply with instructions → Claude continues
```

**No daemon. Each hook = one notification = one response.**

## Manual Setup

If you prefer manual configuration, see [User Guide](docs/user-guide.md).

## Documentation

- [User Guide](docs/user-guide.md) - Setup, commands, hook patterns
- [Contributor Guide](docs/contributor-guide.md) - Architecture, testing

## License

MIT
