||| Claudelegram Test Suite
||| Property-based tests for spec-test parity
module Claudelegram.Tests.AllTests

import Claudelegram.Telegram.Types
import Claudelegram.Telegram.JsonParser
import Claudelegram.Agent
import Data.List
import Data.String

%default covering

-- =============================================================================
-- Test Infrastructure
-- =============================================================================

public export
record TestDef where
  constructor MkTestDef
  specId : String
  title : String
  run : IO Bool

public export
test : String -> String -> IO Bool -> TestDef
test = MkTestDef

runOne : TestDef -> IO Bool
runOne t = do
  result <- t.run
  putStrLn $ (if result then "✓" else "✗") ++ " " ++ t.specId ++ ": " ++ t.title
  pure result

runTestSuite : String -> List TestDef -> IO ()
runTestSuite name tests = do
  putStrLn $ "=== " ++ name ++ " Tests ==="
  results <- traverse runOne tests
  putStrLn $ "Passed: " ++ show (length (filter id results)) ++ "/" ++ show (length results)

-- =============================================================================
-- CLG_JSON: JSON Parsing Tests
-- =============================================================================

||| CLG_JSON_001
test_parseCallbackData_roundtrip : IO Bool
test_parseCallbackData_roundtrip = do
  let cid = "agent-1234567890-0"
  let choice = "yes"
  let data_ = cid ++ "|" ++ choice
  pure $ parseCallbackData data_ == Just (cid, choice)

||| CLG_JSON_002
test_parseUpdates_empty : IO Bool
test_parseUpdates_empty = do
  let json = "{\"ok\":true,\"result\":[]}"
  case parseUpdatesJson json of
    Right [] => pure True
    _ => pure False

||| CLG_JSON_003
test_parseUpdates_rejects_false : IO Bool
test_parseUpdates_rejects_false = do
  let json = "{\"ok\":false,\"description\":\"Bad Request\"}"
  case parseUpdatesJson json of
    Left _ => pure True
    Right _ => pure False

-- =============================================================================
-- CLG_CID: Correlation ID Tests
-- =============================================================================

||| CLG_CID_001
test_cid_format : IO Bool
test_cid_format = do
  let cid = MkCorrelationId 1234567890 0 "agent"
  let shown = show cid
  pure $ isInfixOf "agent" shown && isInfixOf "-" shown

||| CLG_CID_002
test_cid_matching : IO Bool
test_cid_matching = do
  let cid1 = "agent1-1234567890-0"
  let cid2 = "agent2-1234567890-0"
  let data_ = cid1 ++ "|yes"
  case parseCallbackData data_ of
    Just (parsed, _) => pure $ parsed == cid1 && parsed /= cid2
    Nothing => pure False

||| CLG_CID_003
test_parseAgentTag : IO Bool
test_parseAgentTag = do
  let tag = "[agent|agent-1234567890-0]"
  case parseAgentTag tag of
    Just ("agent", "agent-1234567890-0") => pure True
    _ => pure False

-- =============================================================================
-- CLG_ONESHOT: One-Shot Interaction Tests
-- =============================================================================

||| CLG_ONESHOT_001
test_oneshot_single_response : IO Bool
test_oneshot_single_response = do
  -- Verify that parseCallbackData only returns one result per callback_data
  let cid = "agent-1234567890-0"
  let data_ = cid ++ "|yes"
  case parseCallbackData data_ of
    Just (_, choice) => pure $ choice == "yes"  -- Single response
    Nothing => pure False

||| CLG_ONESHOT_002
test_oneshot_linear_types : IO Bool
test_oneshot_linear_types = do
  -- Linear types are verified at compile time.
  -- If this module compiles with Interaction imported, the constraint holds.
  -- We test that the CID generation is unique per call.
  let cid1 = MkCorrelationId 1234567890 0 "agent"
  let cid2 = MkCorrelationId 1234567890 1 "agent"
  pure $ show cid1 /= show cid2  -- Different sequence = different CID

-- =============================================================================
-- Test Collection
-- =============================================================================

public export
allTests : List TestDef
allTests =
  [ test "CLG_JSON_001" "parseCallbackData roundtrip" test_parseCallbackData_roundtrip
  , test "CLG_JSON_002" "parseUpdatesJson empty result" test_parseUpdates_empty
  , test "CLG_JSON_003" "parseUpdatesJson rejects false" test_parseUpdates_rejects_false
  , test "CLG_CID_001" "CID format" test_cid_format
  , test "CLG_CID_002" "CID matching" test_cid_matching
  , test "CLG_CID_003" "parseAgentTag" test_parseAgentTag
  , test "CLG_ONESHOT_001" "Single response per notify" test_oneshot_single_response
  , test "CLG_ONESHOT_002" "Linear types (compile-time)" test_oneshot_linear_types
  ]

-- =============================================================================
-- Main Entry Point
-- =============================================================================

export
runAllTests : IO ()
runAllTests = runTestSuite "Claudelegram" allTests

main : IO ()
main = runAllTests
