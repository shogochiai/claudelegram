# Claudelegram Tests

Property-based tests are located in `test/Test/`:

- `JsonParser.idr` - JSON parsing roundtrips and edge cases
- `Agent.idr` - CID generation and tag parsing
- `Matching.idr` - CID matching behavior

## Running Tests

```bash
# With pack
pack build claudelegram-test
pack run claudelegram-test

# Integration tests
./test/integration.sh
```

## Test Coverage

| Module | Test File | Properties |
|--------|-----------|------------|
| JsonParser | Test/JsonParser.idr | 7 |
| Agent | Test/Agent.idr | 7 |
| LongPoll (matching) | Test/Matching.idr | 5 |
| Interaction | (type-level) | N/A |

The `Interaction` module's one-shot guarantees are enforced at compile-time via linear types, not runtime tests.
