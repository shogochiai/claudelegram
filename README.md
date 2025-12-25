# claudelegram

Human-in-the-loop orchestration via Telegram for Claude Code.

When Claude wants to run a command, you get a Telegram notification with Allow/Deny buttons.

## Quick Start

```bash
# Build
git clone https://github.com/user/claudelegram
cd claudelegram
pack build claudelegram

# Setup (interactive wizard)
./build/exec/claudelegram init
```

The `init` wizard guides you through:
1. Creating a Telegram bot
2. Getting your chat ID
3. Testing the connection
4. Configuring Claude Code hooks

## How It Works

```
Claude Code wants to run `rm -rf /tmp/test`
    ↓
Hook triggers claudelegram
    ↓
You get Telegram notification: [Allow] [Deny]
    ↓
You tap Allow
    ↓
Claude Code proceeds
```

**No daemon. Each hook call = one notification = one response.**

## Manual Setup

If you prefer manual configuration, see [User Guide](docs/user-guide.md).

## Documentation

- [User Guide](docs/user-guide.md) - Setup, commands, hook patterns
- [Contributor Guide](docs/contributor-guide.md) - Architecture, testing

## License

MIT
