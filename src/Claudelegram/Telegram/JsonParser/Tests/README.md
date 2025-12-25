# JsonParser Tests

Property-based tests: `test/Test/JsonParser.idr`

## Properties

| Property | Description |
|----------|-------------|
| prop_parseCallbackData_roundtrip | Roundtrip: parsing well-formed callback_data works |
| prop_parseCallbackData_rejects_no_pipe | Rejects strings without pipe separator |
| prop_parseCallbackData_correct_split | Correctly splits CID and choice |
| prop_parseCallbackData_empty | Empty string returns Nothing |
| prop_parseCallbackData_single_pipe | Single pipe returns empty parts |
| prop_parseUpdates_empty_result | Parses empty result array |
| prop_parseUpdates_rejects_false | Rejects ok:false responses |

## Run

```bash
pack run claudelegram-test
```
