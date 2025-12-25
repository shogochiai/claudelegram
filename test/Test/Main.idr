||| Test runner for claudelegram property-based tests
module Test.Main

import Hedgehog
import Test.JsonParser
import Test.Agent
import Test.Matching

%default total

||| Run all property-based tests
export
main : IO ()
main = test [
    jsonParserProps
  , agentProps
  , matchingProps
  ]
