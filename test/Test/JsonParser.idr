||| Property-based tests for JSON parser
module Test.JsonParser

import Hedgehog
import Claudelegram.Telegram.JsonParser
import Claudelegram.Telegram.Types
import Data.String
import Data.List

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
  ]
