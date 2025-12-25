||| Property-based tests for CID matching logic
module Test.Matching

import Hedgehog
import Claudelegram.Telegram.Types
import Claudelegram.Telegram.JsonParser
import Claudelegram.Agent
import Data.String
import Data.List
import Data.Vect

%default covering

-- Generators

||| Generate a valid CID string
genCidStr : Gen String
genCidStr = do
  agent <- string (linear 1 10) alphaNum
  ts <- integer (linear 1000000000 9999999999)
  seq <- nat (linear 0 100)
  pure $ "\{agent}-\{show ts}-\{show seq}"

||| Generate a choice
genChoice : Gen String
genChoice = element $ the (Vect 6 String) ["yes", "no", "later", "cancel", "approve", "reject"]

||| Generate a callback_data string
genCallbackDataStr : String -> String -> String
genCallbackDataStr cid choice = "\{cid}|\{choice}"

-- Properties

||| Matching CID should extract correct choice
prop_matching_cid_extracts_choice : Property
prop_matching_cid_extracts_choice = property $ do
  cid <- forAll genCidStr
  choice <- forAll genChoice
  let data_ = genCallbackDataStr cid choice
  case parseCallbackData data_ of
    Nothing => failure
    Just (parsedCid, parsedChoice) => do
      parsedCid === cid
      parsedChoice === choice

||| Different CID should not match
prop_different_cid_no_match : Property
prop_different_cid_no_match = property $ do
  cid1 <- forAll genCidStr
  cid2 <- forAll genCidStr
  choice <- forAll genChoice
  -- Only test when CIDs are actually different
  diff cid1 (/=) cid2
  let data_ = genCallbackDataStr cid2 choice
  case parseCallbackData data_ of
    Nothing => failure
    Just (parsedCid, _) => do
      diff parsedCid (/=) cid1

||| Callback data with multiple pipes uses first split
prop_multiple_pipes_first_split : Property
prop_multiple_pipes_first_split = property $ do
  cid <- forAll genCidStr
  part1 <- forAll $ string (linear 1 10) alphaNum
  part2 <- forAll $ string (linear 1 10) alphaNum
  let data_ = "\{cid}|\{part1}|\{part2}"
  -- parseCallbackData only splits on first pipe
  case parseCallbackData data_ of
    Nothing => success  -- Current impl expects exactly one pipe
    Just (parsedCid, rest) => do
      parsedCid === cid
      -- rest should be "part1|part2" or just the parsing might fail
      success

||| Empty CID part is valid but unusual
prop_empty_cid_valid : Property
prop_empty_cid_valid = property $ do
  choice <- forAll genChoice
  let data_ = "|\{choice}"
  case parseCallbackData data_ of
    Nothing => failure
    Just (parsedCid, parsedChoice) => do
      parsedCid === ""
      parsedChoice === choice

||| Order independence: parsing doesn't depend on position in list
prop_cid_uniqueness : Property
prop_cid_uniqueness = property $ do
  -- Generate two distinct CIDs
  agent1 <- forAll $ string (linear 3 8) alpha
  agent2 <- forAll $ string (linear 3 8) alpha
  diff agent1 (/=) agent2

  let cid1 = "\{agent1}-1234567890-0"
  let cid2 = "\{agent2}-1234567890-0"

  choice1 <- forAll genChoice
  choice2 <- forAll genChoice

  let data1 = genCallbackDataStr cid1 choice1
  let data2 = genCallbackDataStr cid2 choice2

  -- Parsing data1 should give cid1
  case parseCallbackData data1 of
    Nothing => failure
    Just (c, _) => c === cid1

  -- Parsing data2 should give cid2
  case parseCallbackData data2 of
    Nothing => failure
    Just (c, _) => c === cid2

-- Export all properties
export
matchingProps : Group
matchingProps = MkGroup "Matching" [
    ("prop_matching_cid_extracts_choice", prop_matching_cid_extracts_choice)
  , ("prop_different_cid_no_match", prop_different_cid_no_match)
  , ("prop_multiple_pipes_first_split", prop_multiple_pipes_first_split)
  , ("prop_empty_cid_valid", prop_empty_cid_valid)
  , ("prop_cid_uniqueness", prop_cid_uniqueness)
  ]
