# LongPoll Tests

Property-based tests: `test/Test/Matching.idr`

## Properties

| Property | Description |
|----------|-------------|
| prop_matching_cid_extracts_choice | Matching CID extracts correct choice |
| prop_different_cid_no_match | Different CID does not match |
| prop_multiple_pipes_first_split | Multiple pipes uses first split |
| prop_empty_cid_valid | Empty CID part is valid |
| prop_cid_uniqueness | Each CID is unique and correctly routed |

## Run

```bash
pack run claudelegram-test
```
