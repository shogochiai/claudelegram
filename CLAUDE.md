# Project Agent Instructions

## Claude Code Hook Integration

claudelegram provides one-shot synchronous interaction with humans via Telegram.

### Usage in Claude Code Hooks

```bash
# In your hook script, use synchronous notify:
response=$(claudelegram notify "Deploy to production?" -c "yes,no,later")

# $response will be "yes", "no", or "later" based on button pressed
if [ "$response" = "yes" ]; then
  # proceed with deployment
fi
```

### Key Points

- **Option A (sync notify)** is the recommended approach — no daemon required
- Each `notify --choices` call blocks until the human presses a button
- The response is written to stdout for the caller to capture
- CID (Correlation ID) in `callback_data` ensures no response mix-ups
- tmux injection is optional — caller decides how to use the response

### One-Shot Interaction Protocol

1. `notify` generates a unique CID
2. Message sent to Telegram with inline keyboard buttons
3. Each button's `callback_data` = `"CID|CHOICE"`
4. `waitForResponse` polls for callback matching the CID
5. Only the matching response is returned; others are ignored
6. Linear types (`Interaction Pending → Completed`) prevent double-await

---

## Quick Reference

```bash
# Analyze codebase and get recommended actions
lazy core ask <target_dir>

# Phase 1 (Vibe Bootstrap): Focus on test discovery
lazy core ask <target_dir> --steps 4

# Phase 2 (Spec Emergence): Bidirectional parity
lazy core ask <target_dir> --steps 1,2,3

# Phase 3 (TDVC Loop): Chase Zero Gap, find implicit bugs, and Vibe More
lazy core ask <target_dir> --steps 1,2,3,4
lazy core ask <target_dir> --steps 5
```

## Interpreting Output

- **URGENT** actions: Execute immediately
- **High** priority: Address in current session
- **Medium/Low**: Queue for later

## Policy Mapping

`lazy core ask` converts gaps → signals → recommendations.
Follow recommendations to maintain project health.
