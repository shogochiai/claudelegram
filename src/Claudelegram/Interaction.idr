||| One-shot Interaction with linear type enforcement
||| Ensures Pending→Completed transition happens exactly once
module Claudelegram.Interaction

import Claudelegram.Config
import Claudelegram.Agent
import Claudelegram.Telegram.LongPoll

%default covering

||| Interaction phase
||| Pending: waiting for human response
||| Completed: response received (terminal state)
public export
data Phase = Pending | Completed

||| Interaction record with phase tracking
||| The phase parameter enforces state transitions at the type level
public export
record Interaction (p : Phase) where
  constructor MkInteraction
  cid : CorrelationId
  agentName : String
  timeout : Nat
  startOffset : Integer

||| Create a new pending interaction
||| Generates a fresh CID and initializes offset to 0
export
mkInteraction : Config -> (timeout : Nat) -> IO (Interaction Pending)
mkInteraction cfg timeout = do
  cid <- newCorrelationId cfg.agentName 0
  pure $ MkInteraction cid cfg.agentName timeout 0

||| Create a pending interaction with a specific starting offset
||| Useful when you want to skip already-processed updates
export
mkInteractionWithOffset : Config -> (timeout : Nat) -> (offset : Integer) -> IO (Interaction Pending)
mkInteractionWithOffset cfg timeout offset = do
  cid <- newCorrelationId cfg.agentName 0
  pure $ MkInteraction cid cfg.agentName timeout offset

||| Await response (one-shot: consumes Pending, returns Completed)
|||
||| The linear argument `(1 _ : Interaction Pending)` ensures:
||| 1. The Pending interaction is consumed exactly once
||| 2. Cannot await on the same interaction twice
||| 3. Cannot discard a Pending interaction without awaiting
|||
||| Returns either an error message or the (response, completed interaction)
export
await1 : (1 _ : Interaction Pending) -> Config -> IO (Either String (String, Interaction Completed))
await1 (MkInteraction cid agent timeout offset) cfg = do
  result <- waitForResponse cfg cid timeout offset
  case result of
    Left err => pure (Left err)
    Right response => pure (Right (response, MkInteraction cid agent timeout offset))

||| Get the CID from any interaction (for logging/display)
export
getCid : Interaction p -> CorrelationId
getCid i = i.cid

||| Get the agent name from any interaction
export
getAgentName : Interaction p -> String
getAgentName i = i.agentName

||| Show instance for Pending interactions
export
Show (Interaction Pending) where
  show i = "Interaction(\{show i.cid}, phase=Pending)"

||| Show instance for Completed interactions
export
Show (Interaction Completed) where
  show i = "Interaction(\{show i.cid}, phase=Completed)"
