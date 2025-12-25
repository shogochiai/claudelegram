||| Property-based tests for JSON parser
module Test.JsonParser

import Hedgehog
import Claudelegram.Telegram.JsonParser
import Claudelegram.Telegram.Types
import Data.String
import Data.List
import Data.Maybe

%default covering

-- Generators

||| Generate a valid CID string (agent-timestamp-seq format)
genCid : Gen String
genCid = do
  agent <- string (linear 1 10) alphaNum
  ts <- integer (linear 1000000000 9999999999)
  seq <- nat (linear 0 100)
  pure $ "\{agent}-\{show ts}-\{show seq}"

||| Generate a valid choice string
genChoice : Gen String
genChoice = string (linear 1 20) alphaNum

||| Generate callback_data in "CID|CHOICE" format
genCallbackData : Gen String
genCallbackData = do
  cid <- genCid
  choice <- genChoice
  pure $ "\{cid}|\{choice}"

-- Properties

||| parseCallbackData roundtrip: parsing a well-formed callback_data works
prop_parseCallbackData_roundtrip : Property
prop_parseCallbackData_roundtrip = property $ do
  cid <- forAll genCid
  choice <- forAll genChoice
  let data_ = "\{cid}|\{choice}"
  parseCallbackData data_ === Just (cid, choice)

||| parseCallbackData rejects strings without pipe
prop_parseCallbackData_rejects_no_pipe : Property
prop_parseCallbackData_rejects_no_pipe = property $ do
  s <- forAll $ string (linear 1 50) alphaNum
  -- No pipe in generated string
  parseCallbackData s === Nothing

||| parseCallbackData extracts correct parts
prop_parseCallbackData_correct_split : Property
prop_parseCallbackData_correct_split = property $ do
  cid <- forAll genCid
  choice <- forAll genChoice
  case parseCallbackData "\{cid}|\{choice}" of
    Nothing => failure
    Just (c, ch) => do
      c === cid
      ch === choice

||| Empty callback_data returns Nothing
prop_parseCallbackData_empty : Property
prop_parseCallbackData_empty = property $ do
  parseCallbackData "" === Nothing

||| Single pipe returns empty parts
prop_parseCallbackData_single_pipe : Property
prop_parseCallbackData_single_pipe = property $ do
  parseCallbackData "|" === Just ("", "")

||| parseUpdatesJson handles empty result array
prop_parseUpdates_empty_result : Property
prop_parseUpdates_empty_result = property $ do
  let json = "{\"ok\":true,\"result\":[]}"
  case parseUpdatesJson json of
    Right [] => success
    Right _ => failure
    Left _ => failure

||| parseUpdatesJson rejects ok:false
prop_parseUpdates_rejects_false : Property
prop_parseUpdates_rejects_false = property $ do
  let json = "{\"ok\":false,\"description\":\"Bad Request\"}"
  case parseUpdatesJson json of
    Left _ => success
    Right _ => failure

-- =============================================================================
-- Skip* Functions Tests (via parseUpdatesJson integration)
-- These test internal skip* functions by providing JSON that exercises them
-- =============================================================================

||| Test skipWs via parseUpdatesJson with whitespace
prop_skipWs_via_integration : Property
prop_skipWs_via_integration = property $ do
  -- JSON with various whitespace patterns
  let json = "  { \"ok\" : true , \"result\" : [ ] }  "
  case parseUpdatesJson json of
    Right [] => success
    _ => failure

||| Test skipNull via parseUpdatesJson with null fields
prop_skipNull_via_integration : Property
prop_skipNull_via_integration = property $ do
  let json = "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"message_id\":1,\"date\":0,\"chat\":{\"id\":1,\"type\":\"private\"},\"text\":null}}]}"
  case parseUpdatesJson json of
    Right [_] => success
    _ => failure

||| Test parseJsonInt via parseUpdatesJson with various integers
prop_parseJsonInt_via_integration : Property
prop_parseJsonInt_via_integration = property $ do
  -- Large positive integer
  let json1 = "{\"ok\":true,\"result\":[{\"update_id\":999999999}]}"
  case parseUpdatesJson json1 of
    Right [_] => success
    _ => failure

||| Test skipJsonArray via nested arrays in message
prop_skipJsonArray_via_integration : Property
prop_skipJsonArray_via_integration = property $ do
  -- JSON with nested array (entities field)
  let json = "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"message_id\":1,\"date\":0,\"chat\":{\"id\":1,\"type\":\"private\"},\"entities\":[{\"type\":\"bold\"}]}}]}"
  case parseUpdatesJson json of
    Right [_] => success
    _ => failure

||| Test skipJsonObject via nested objects
prop_skipJsonObject_via_integration : Property
prop_skipJsonObject_via_integration = property $ do
  -- JSON with deeply nested objects
  let json = "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"message_id\":1,\"date\":0,\"chat\":{\"id\":1,\"type\":\"private\",\"permissions\":{\"can_send\":true}}}}]}"
  case parseUpdatesJson json of
    Right [_] => success
    _ => failure

||| Test skipJsonValue with all JSON types
prop_skipJsonValue_all_types : Property
prop_skipJsonValue_all_types = property $ do
  -- JSON with string, number, boolean, null, array, object
  let json = "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"message_id\":1,\"date\":0,\"chat\":{\"id\":1,\"type\":\"private\"},\"str_field\":\"hello\",\"num_field\":42,\"bool_field\":true,\"null_field\":null,\"arr_field\":[1,2],\"obj_field\":{\"x\":1}}}]}"
  case parseUpdatesJson json of
    Right [_] => success
    _ => failure

||| Test skipObjectFields with multiple fields to skip
prop_skipObjectFields_multiple : Property
prop_skipObjectFields_multiple = property $ do
  -- JSON with many fields that need skipping before reaching target
  let json = "{\"ok\":true,\"result\":[{\"a\":1,\"b\":2,\"c\":3,\"d\":4,\"e\":5,\"update_id\":100}]}"
  case parseUpdatesJson json of
    Right [_] => success
    _ => failure

||| Test skipArrayElements with multiple elements
prop_skipArrayElements_multiple : Property
prop_skipArrayElements_multiple = property $ do
  -- JSON with array containing multiple objects
  let json = "{\"ok\":true,\"result\":[{\"update_id\":1},{\"update_id\":2},{\"update_id\":3}]}"
  case parseUpdatesJson json of
    Right xs => length xs === 3
    _ => failure

||| parseCallbackData rejects multiple pipes (behavior check)
prop_parseCallbackData_multiple_pipes : Property
prop_parseCallbackData_multiple_pipes = property $ do
  -- With multiple pipes, split creates more than 2 parts
  case parseCallbackData "a|b|c" of
    Nothing => success  -- Rejects as expected
    Just _ => failure

-- Export all properties
export
jsonParserProps : Group
jsonParserProps = MkGroup "JsonParser" [
    ("prop_parseCallbackData_roundtrip", prop_parseCallbackData_roundtrip)
  , ("prop_parseCallbackData_rejects_no_pipe", prop_parseCallbackData_rejects_no_pipe)
  , ("prop_parseCallbackData_correct_split", prop_parseCallbackData_correct_split)
  , ("prop_parseCallbackData_empty", prop_parseCallbackData_empty)
  , ("prop_parseCallbackData_single_pipe", prop_parseCallbackData_single_pipe)
  , ("prop_parseUpdates_empty_result", prop_parseUpdates_empty_result)
  , ("prop_parseUpdates_rejects_false", prop_parseUpdates_rejects_false)
  -- Skip* integration tests
  , ("prop_skipWs_via_integration", prop_skipWs_via_integration)
  , ("prop_skipNull_via_integration", prop_skipNull_via_integration)
  , ("prop_parseJsonInt_via_integration", prop_parseJsonInt_via_integration)
  , ("prop_skipJsonArray_via_integration", prop_skipJsonArray_via_integration)
  , ("prop_skipJsonObject_via_integration", prop_skipJsonObject_via_integration)
  , ("prop_skipJsonValue_all_types", prop_skipJsonValue_all_types)
  , ("prop_skipObjectFields_multiple", prop_skipObjectFields_multiple)
  , ("prop_skipArrayElements_multiple", prop_skipArrayElements_multiple)
  , ("prop_parseCallbackData_multiple_pipes", prop_parseCallbackData_multiple_pipes)
  ]
