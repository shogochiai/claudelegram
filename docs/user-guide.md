# User Guide

## Quick Start

```bash
# 1. Build
git clone https://github.com/user/claudelegram
cd claudelegram
pack build claudelegram

# 2. Run setup wizard
./build/exec/claudelegram init
```

The `init` wizard will guide you through:
1. Creating a Telegram bot via @BotFather
2. Getting your chat ID
3. Testing the connection
4. Configuring Claude Code hooks

---

## Manual Setup

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
- [pack](https://github.com/stefan-hoeck/idris2-pack) (Idris2 package manager)
- curl

```bash
git clone https://github.com/user/claudelegram
cd claudelegram
pack build claudelegram
```

The executable will be at `./build/exec/claudelegram`.

### 3. Configure Environment

```bash
export TELEGRAM_BOT_TOKEN="123456:ABC-xyz..."
export TELEGRAM_CHAT_ID="987654321"

# Optional
export CLAUDELEGRAM_AGENT="claude"        # Agent name for logging
export CLAUDELEGRAM_POLL_TIMEOUT="30"     # Timeout in seconds
```

Add these to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) for persistence.

### 4. Configure Claude Code Hooks

Add to your project's `.claude/settings.local.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "claudelegram hook PreToolUse"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "claudelegram hook Notification"
          }
        ]
      }
    ]
  }
}
```

This configuration:
- Asks for Allow/Deny on all permission requests
- Notifies you when Claude is idle and waiting for input (reply via Telegram)

---

## Commands

### init

Interactive setup wizard. Guides you through bot creation, configuration, and hook setup.

```bash
claudelegram init
```

### hook

Run as a Claude Code hook handler. Reads tool info from stdin, sends Telegram notification, outputs JSON response.

```bash
claudelegram hook <PreToolUse|PostToolUse|Notification>
```

**Hook Events:**

| Event | Description | Response |
|-------|-------------|----------|
| `PreToolUse` | Before tool execution | Allow/Deny buttons, returns permission JSON |
| `PostToolUse` | After tool completes | One-way notification |
| `Notification` | System alerts (e.g., `idle_prompt`) | Waits for text reply, returns as `stopReason` |

**Note:** For `idle_prompt` notifications, claudelegram sends a message and waits for your text reply. Your reply is passed back to Claude Code, allowing you to give instructions remotely via Telegram.

### notify

Ask for user input. Two modes available:

**Button mode** (with `-c`): Shows buttons, waits for selection.
```bash
response=$(claudelegram notify "Deploy to production?" -c "yes,no,later")
echo "User chose: $response"
```

**Reply mode** (without `-c`): Waits for text reply.
```bash
response=$(claudelegram notify "What should I do next?")
echo "User said: $response"
```

The response is written to stdout.

### send

Send a one-way message. Does not wait for response.

```bash
claudelegram send "Build completed successfully"
```

### poll

Start long-polling daemon (for advanced use cases).

```bash
claudelegram poll
```

### inject

Inject response to tmux session (for advanced use cases).

```bash
claudelegram inject <session> <response>
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

## Claude Code Integration Patterns

### Pattern 1: Approve All Permission Requests + Idle Prompt

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": "claudelegram hook PreToolUse"}]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [{"type": "command", "command": "claudelegram hook Notification"}]
      }
    ]
  }
}
```

### Pattern 2: Approve Only Bash Commands

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "claudelegram hook PreToolUse"}]
      }
    ]
  }
}
```

### Pattern 3: Approve File Modifications

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Edit",
        "hooks": [{"type": "command", "command": "claudelegram hook PreToolUse"}]
      },
      {
        "matcher": "Write",
        "hooks": [{"type": "command", "command": "claudelegram hook PreToolUse"}]
      }
    ]
  }
}
```

### Pattern 4: Notify After Tool Completion

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [{"type": "command", "command": "claudelegram hook PostToolUse"}]
      }
    ]
  }
}
```

---

## Troubleshooting

### "Configuration error: Missing TELEGRAM_BOT_TOKEN"

Set environment variables before running:
```bash
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat-id"
```

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

### Hook not triggering

- Verify the path to claudelegram is absolute and correct
- Check Claude Code logs for hook errors
- Ensure the hook JSON syntax is valid

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

**Q: What happens if I don't respond in time?**

The hook returns "ask" which tells Claude Code to prompt you in the terminal instead.

**Q: How secure is this?**

If your Telegram account is compromised, an attacker can approve any action. This tool is designed for convenience, not high-security environments. Use at your own risk.
