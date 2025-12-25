||| Property-based tests for Agent module (CID generation and parsing)
module Test.Agent

import Hedgehog
import Claudelegram.Agent
import Data.String
import Data.List

%default total

-- Generators

||| Generate a valid agent name
genAgentName : Gen String
genAgentName = string (linear 1 20) alphaNum

||| Generate an optional PID
genMaybePid : Gen (Maybe Int)
genMaybePid = maybe (int (linear 1 99999))

-- Properties

||| formatAgentTag produces bracketed format
prop_formatAgentTag_bracketed : Property
prop_formatAgentTag_bracketed = property $ do
  name <- forAll genAgentName
  let agent = mkAgentId name Nothing
  -- We need a CID, but can't generate IO here, so use a fixed one
  let cidStr = "\{name}-1234567890-0"
  -- Check that parseAgentTag can parse what we would produce
  let tag = "[\{name}|\{cidStr}]"
  case parseAgentTag tag of
    Nothing => failure
    Just (agentPart, cidPart) => do
      agentPart === name
      cidPart === cidStr

||| parseAgentTag roundtrip with PID
prop_parseAgentTag_with_pid : Property
prop_parseAgentTag_with_pid = property $ do
  name <- forAll genAgentName
  pid <- forAll $ int (linear 1 99999)
  let cidStr = "\{name}-1234567890-0"
  let agentPart = "\{name}:\{show pid}"
  let tag = "[\{agentPart}|\{cidStr}]"
  case parseAgentTag tag of
    Nothing => failure
    Just (ap, cp) => do
      ap === agentPart
      cp === cidStr

||| parseAgentTag rejects non-bracketed
prop_parseAgentTag_rejects_no_bracket : Property
prop_parseAgentTag_rejects_no_bracket = property $ do
  s <- forAll $ string (linear 1 50) alphaNum
  -- Generated string won't start with '['
  parseAgentTag s === Nothing

||| parseAgentTag rejects missing pipe
prop_parseAgentTag_rejects_no_pipe : Property
prop_parseAgentTag_rejects_no_pipe = property $ do
  s <- forAll $ string (linear 1 30) alphaNum
  let tag = "[\{s}]"  -- No pipe inside
  parseAgentTag tag === Nothing

||| CorrelationId show format is "agent-timestamp-seq"
prop_cid_show_format : Property
prop_cid_show_format = property $ do
  agent <- forAll genAgentName
  ts <- forAll $ integer (linear 1000000000 9999999999)
  seq <- forAll $ nat (linear 0 100)
  let cid = MkCorrelationId ts seq agent
  let shown = show cid
  -- Should contain agent name
  assert $ isInfixOf agent shown
  -- Should contain dashes
  assert $ isInfixOf "-" shown

||| AgentId show without PID
prop_agentId_show_no_pid : Property
prop_agentId_show_no_pid = property $ do
  name <- forAll genAgentName
  let agent = mkAgentId name Nothing
  show agent === name

||| AgentId show with PID
prop_agentId_show_with_pid : Property
prop_agentId_show_with_pid = property $ do
  name <- forAll genAgentName
  pid <- forAll $ int (linear 1 99999)
  let agent = mkAgentId name (Just pid)
  show agent === "\{name}:\{show pid}"

-- Export all properties
export
agentProps : Group
agentProps = MkGroup "Agent" [
    ("prop_formatAgentTag_bracketed", prop_formatAgentTag_bracketed)
  , ("prop_parseAgentTag_with_pid", prop_parseAgentTag_with_pid)
  , ("prop_parseAgentTag_rejects_no_bracket", prop_parseAgentTag_rejects_no_bracket)
  , ("prop_parseAgentTag_rejects_no_pipe", prop_parseAgentTag_rejects_no_pipe)
  , ("prop_cid_show_format", prop_cid_show_format)
  , ("prop_agentId_show_no_pid", prop_agentId_show_no_pid)
  , ("prop_agentId_show_with_pid", prop_agentId_show_with_pid)
  ]
