# Contributor Guide

## Requirements

- [Idris2](https://github.com/idris-lang/Idris2) 0.8.0+
- [pack](https://github.com/stefan-hoeck/idris2-pack) (for running tests)
- curl

## Build & Run

```bash
# Build main executable
idris2 --build claudelegram.ipkg
./build/exec/claudelegram --help

# Build with pack (includes dependencies)
pack build claudelegram
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      CLI (Main.idr)                     │
├─────────────────────────────────────────────────────────┤
│  Cli.idr          │  Config.idr      │  Agent.idr      │
│  (arg parsing)    │  (env vars)      │  (CID gen)      │
├───────────────────┴──────────────────┴─────────────────┤
│                  Interaction.idr                        │
│            (Pending → Completed, linear types)          │
├─────────────────────────────────────────────────────────┤
│                    Telegram/                            │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────┐  │
│  │  Api.idr    │  │ LongPoll.idr│  │ JsonParser.idr │  │
│  │ (HTTP calls)│  │(CID matching)│  │ (response parse)│ │
│  └─────────────┘  └─────────────┘  └────────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Injection/                           │
│  ┌─────────────┐  ┌─────────────┐                      │
│  │  Tmux.idr   │  │  Fifo.idr   │   (optional)        │
│  └─────────────┘  └─────────────┘                      │
└─────────────────────────────────────────────────────────┘
```

### Module Descriptions

| Module | Purpose |
|--------|---------|
| `Main.idr` | CLI entry point, command dispatch |
| `Config.idr` | Load configuration from environment variables |
| `Cli.idr` | Parse command-line arguments |
| `Agent.idr` | Generate and parse AgentId, CorrelationId |
| `Interaction.idr` | One-shot state machine with linear types |
| `Telegram/Api.idr` | HTTP calls to Telegram Bot API |
| `Telegram/LongPoll.idr` | Poll for updates, match by CID |
| `Telegram/JsonParser.idr` | Hand-rolled JSON parser |
| `Injection/Tmux.idr` | Inject keystrokes via tmux |
| `Injection/Fifo.idr` | Write to named pipes |

---

## Key Concepts

### Correlation ID (CID)

Every `notify` generates a unique CID in the format:
```
agentName-timestamp-sequence
```

Example: `claude-1735123456-0`

The CID is embedded in button `callback_data` as `"CID|CHOICE"`. When polling for responses, only callbacks with matching CID are accepted. This prevents response mix-ups between concurrent requests.

### One-Shot Interaction (Linear Types)

The `Interaction` module uses Idris2's linear types to enforce one-shot semantics:

```idris
data Phase = Pending | Completed

record Interaction (p : Phase) where
  ...

await1 : (1 _ : Interaction Pending) -> Config -> IO (Either String (String, Interaction Completed))
```

The `(1 _ : ...)` means:
- The `Pending` interaction must be used exactly once
- Cannot await the same interaction twice (compile error)
- Cannot silently discard a `Pending` (compile error)

This provides compile-time guarantees that each request gets exactly one response.

### No Daemon

Unlike typical bot architectures, claudelegram is stateless:

1. `notify` starts a new process
2. Sends message to Telegram
3. Polls for matching callback
4. Returns response and exits

No daemon, no state files, no IPC. Each call is independent.

---

## Testing

### Property-Based Tests (Hedgehog)

```bash
# Build and run
pack build claudelegram-test
pack run claudelegram-test
```

Tests are in `test/Test/`:
- `JsonParser.idr` - JSON parsing properties
- `Agent.idr` - CID generation and parsing
- `Matching.idr` - CID matching behavior

### Integration Tests

```bash
export TELEGRAM_BOT_TOKEN="..."
export TELEGRAM_CHAT_ID="..."
./test/integration.sh
```

Includes interactive tests that require pressing buttons on Telegram.

### Manual Testing

1. `claudelegram send "ping"` → verify message arrives
2. `claudelegram notify "test" -c "a,b"` → press button → verify stdout
3. Run two parallel `notify` calls → verify no cross-talk

---

## Specifications

SPEC.toml files document invariants for each module:

| File | Contents |
|------|----------|
| `src/Claudelegram/Agent/SPEC.toml` | CID format, tag parsing |
| `src/Claudelegram/Interaction/SPEC.toml` | Linear type guarantees |
| `src/Claudelegram/Telegram/JsonParser/SPEC.toml` | Parsing properties |
| `src/Claudelegram/Telegram/LongPoll/SPEC.toml` | CID matching behavior |

Use `lazy core ask` to analyze:
```bash
lazy core ask src --steps 4
```

---

## Contributing

### Workflow

1. Fork the repository
2. Create a feature branch
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. Write tests first (TDD)
4. Implement the feature
5. Ensure all tests pass
   ```bash
   pack run claudelegram-test
   ```
6. Commit with descriptive message
7. Push and open a Pull Request

### Code Style

- Follow existing Idris2 conventions
- Use `%default covering` for modules with IO
- Use `%default total` for pure modules
- Add doc comments (`|||`) for public functions
- Keep functions small and focused

### Adding New Features

1. Add `SPEC.toml` documenting invariants
2. Write property-based tests in `test/Test/`
3. Implement the feature
4. Update docs if user-facing
5. Update README if major feature

### Commit Messages

Follow conventional commits:
```
feat: add webhook mode
fix: handle empty callback_data
test: add property tests for X
docs: update user guide
refactor: simplify JSON parser
```

---

## Future Work

- [ ] Webhook mode (alternative to polling)
- [ ] Better error messages with suggestions
- [ ] Support for `reply_to_message` (text responses)
- [ ] Multi-row button layouts
- [ ] Localization support
