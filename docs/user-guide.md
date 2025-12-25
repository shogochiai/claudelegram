# User Guide

## Setup

### 1. Create a Telegram Bot

1. Open Telegram and message [@BotFather](https://t.me/botfather)
2. Send `/newbot` and follow the prompts
3. Save the **Bot Token** (looks like `123456:ABC-xyz...`)
4. Message your new bot (just say "hi")
5. Get your **Chat ID**:
   ```bash
   curl "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
   ```
   Look for `"chat":{"id":123456789}` in the response

### 2. Build

Requirements:
- [Idris2](https://github.com/idris-lang/Idris2) 0.8.0+
- curl

```bash
git clone git@github.com:shogochiai/claudelegram.git
cd claudelegram
idris2 --build claudelegram.ipkg
```

The executable will be at `./build/exec/claudelegram`.

### 3. Configure

```bash
export TELEGRAM_BOT_TOKEN="123456:ABC-xyz..."
export TELEGRAM_CHAT_ID="987654321"

# Optional
export CLAUDELEGRAM_AGENT="claude"        # Agent name for logging
export CLAUDELEGRAM_POLL_TIMEOUT="30"     # Timeout in seconds
```

Add these to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) for persistence.

---

## Commands

### notify

Ask for approval with buttons. Blocks until response.

```bash
claudelegram notify "message" -c "option1,option2,option3"
```

The selected option is written to stdout.

**Example:**
```bash
response=$(claudelegram notify "Deploy to production?" -c "yes,no,later")
echo "User chose: $response"
```

### send

Send a one-way message. Does not wait for response.

```bash
claudelegram send "Build completed successfully"
```

---

## Options

| Option | Description |
|--------|-------------|
| `-c, --choices <list>` | Comma-separated button labels |
| `-T, --timeout <secs>` | Timeout in seconds (default: 30) |
| `-a, --agent <name>` | Agent name for logging |
| `-t, --tmux <session>` | Tmux session for injection |
| `-f, --fifo <path>` | FIFO path for injection |

---

## Claude Code Integration

### Basic Hook

Create a hook script that asks for approval:

```bash
#!/bin/bash
# ~/.claude/hooks/before-command.sh

response=$(claudelegram notify "Run: $1" -c "yes,no")
if [ "$response" = "yes" ]; then
  exit 0  # Allow
else
  exit 1  # Deny
fi
```

### Dangerous Command Filter

```bash
#!/bin/bash
# Only ask for dangerous commands

case "$1" in
  *rm\ -rf*|*sudo*|*git\ push\ --force*)
    response=$(claudelegram notify "⚠️ Dangerous: $1" -c "allow,deny")
    [ "$response" = "allow" ] || exit 1
    ;;
esac
```

---

## Troubleshooting

### "curl failed" error

- Check internet connection
- Verify `TELEGRAM_BOT_TOKEN` is correct
- Ensure the bot token hasn't been revoked by BotFather

### "Timeout waiting for response"

- Default timeout is 30 seconds
- Use `-T 120` for longer timeout
- Check if Telegram is accessible (firewall/proxy issues)

### No notification on phone

- Make sure you've messaged the bot at least once
- Verify `TELEGRAM_CHAT_ID` is **your** chat ID, not the bot's
- Check Telegram notification settings on your phone
- Try `claudelegram send "test"` to verify basic connectivity

### Wrong response received

This shouldn't happen due to CID (Correlation ID) matching. Each request has a unique ID, and only responses matching that ID are accepted.

If it does happen, please file an issue with:
- The commands you ran
- The debug output (set `DEBUG=1`)

---

## FAQ

**Q: Can multiple agents run simultaneously?**

Yes. Each `notify` generates a unique Correlation ID (CID), so responses are correctly routed even with parallel calls.

**Q: Does it work offline?**

No. Telegram API requires internet connectivity.

**Q: Can I use this with Claude Desktop?**

This is designed for Claude Code CLI. Claude Desktop would require a different integration approach.

**Q: What if I press the wrong button?**

The response is final and immediate. Run the command again if needed.

**Q: How secure is this?**

If your Telegram account is compromised, an attacker can approve any action. This tool is designed for convenience, not high-security environments. Use at your own risk.

**Q: Can I customize the button layout?**

Currently buttons are displayed in a single row. Multi-row layouts may be added in the future.
