# Interaction Tests

## Type-Level Guarantees

The `Interaction` module uses Idris2's linear types to enforce invariants at compile-time:

```idris
await1 : (1 _ : Interaction Pending) -> Config -> IO (Either String (String, Interaction Completed))
```

The `(1 _ : ...)` ensures:
- A `Pending` interaction is consumed exactly once
- Cannot await the same interaction twice (compile error)
- Cannot discard a `Pending` without awaiting (compile error)

## Why No Runtime Tests?

These invariants are enforced by the type system. Any code that violates them will not compile.

Example of rejected code:
```idris
-- This would NOT compile:
bad : Interaction Pending -> IO ()
bad i = do
  _ <- await1 i cfg  -- First use
  _ <- await1 i cfg  -- ERROR: i already consumed
  pure ()
```

## Integration Tests

The integration test script (`test/integration.sh`) verifies end-to-end behavior including the Interaction flow.
