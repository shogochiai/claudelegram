# Agent Tests

Property-based tests: `test/Test/Agent.idr`

## Properties

| Property | Description |
|----------|-------------|
| prop_formatAgentTag_bracketed | Produces bracketed format |
| prop_parseAgentTag_with_pid | Parses agent tag with PID |
| prop_parseAgentTag_rejects_no_bracket | Rejects non-bracketed strings |
| prop_parseAgentTag_rejects_no_pipe | Rejects tags without pipe |
| prop_cid_show_format | CID show contains agent name and dashes |
| prop_agentId_show_no_pid | AgentId without PID shows just name |
| prop_agentId_show_with_pid | AgentId with PID shows name:pid |

## Run

```bash
pack run claudelegram-test
```
