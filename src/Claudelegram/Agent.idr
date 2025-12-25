||| Agent Identification and Tagging
||| Manages AgentName and Correlation IDs (CID)
module Claudelegram.Agent

import Data.String
import Data.List1
import System.Clock

%default total

||| Agent identifier
public export
record AgentId where
  constructor MkAgentId
  name : String
  pid : Maybe Int

||| Correlation ID for tracking interactions
public export
record CorrelationId where
  constructor MkCorrelationId
  timestamp : Integer
  sequence : Nat
  agentName : String

export
Show AgentId where
  show a = case a.pid of
    Nothing => a.name
    Just p => "\{a.name}:\{show p}"

export
Show CorrelationId where
  show cid = "\{cid.agentName}-\{show cid.timestamp}-\{show cid.sequence}"

||| Format agent tag for message prefix
public export
formatAgentTag : AgentId -> CorrelationId -> String
formatAgentTag agent cid = "[\{show agent}|\{show cid}]"

||| Parse agent tag from message
public export
parseAgentTag : String -> Maybe (String, String)
parseAgentTag s =
  case strUncons s of
    Just ('[', rest) =>
      let (content, after) = break (== ']') rest
          parts = forget $ split (== '|') content
      in case parts of
           [agentPart, cidPart] => Just (agentPart, cidPart)
           _ => Nothing
    _ => Nothing

||| Generate a new correlation ID
export
newCorrelationId : String -> Nat -> IO CorrelationId
newCorrelationId agentName seq = do
  t <- clockTime UTC
  let ts = seconds t
  pure $ MkCorrelationId ts seq agentName

||| Create agent ID from config
public export
mkAgentId : String -> Maybe Int -> AgentId
mkAgentId = MkAgentId

||| Interaction state for an agent
public export
data InteractionState : Type where
  ||| Waiting for human input
  AwaitingInput : (cid : CorrelationId) -> (prompt : String) -> InteractionState
  ||| Awaiting choice selection
  AwaitingChoice : (cid : CorrelationId) -> (options : List String) -> InteractionState
  ||| Completed
  Completed : (cid : CorrelationId) -> (response : String) -> InteractionState
  ||| Cancelled by ESC
  Cancelled : (cid : CorrelationId) -> InteractionState

export
Show InteractionState where
  show (AwaitingInput cid prompt) = "AwaitingInput(\{show cid})"
  show (AwaitingChoice cid opts) = "AwaitingChoice(\{show cid}, \{show (length opts)} options)"
  show (Completed cid resp) = "Completed(\{show cid})"
  show (Cancelled cid) = "Cancelled(\{show cid})"
