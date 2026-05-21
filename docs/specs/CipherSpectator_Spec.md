# CipherSpectator.sol — Full Specification

# CIPHER Protocol | Milestone 0.2

## PURPOSE

CipherSpectator.sol manages the spectator prediction system
for CIPHER. Spectators can watch live matches and stake tokens
on which player they believe will win. When the match concludes,
correct predictors automatically receive a proportional share
of the losing pool. Everything is onchain and automatic.

================================================================

## STRUCTS

================================================================

struct Prediction {
address spectator;
address chosenPlayer; // which player they bet on
uint256 amount; // tokens staked
bool claimed; // always false — auto-distributed
}

struct MatchPredictionPool {
uint256 matchId;
address playerA;
address playerB;
uint256 totalPool; // total tokens in pool
uint256 poolForPlayerA; // tokens bet on playerA
uint256 poolForPlayerB; // tokens bet on playerB
bool predictionsOpen; // false after final round starts
bool resolved; // true after match concludes
address winner; // set on resolution
uint256 spectatorCount; // total unique spectators
}

================================================================

## STATE VARIABLES

================================================================

| Variable              | Type                                            | Description                      |
| --------------------- | ----------------------------------------------- | -------------------------------- |
| owner                 | address                                         | Admin address                    |
| configContract        | address                                         | CipherConfig.sol address         |
| authorizedMatches     | mapping(address => bool)                        | CipherMatch contracts authorized |
| predictionPools       | mapping(uint256 => MatchPredictionPool)         | Pool data per matchId            |
| predictions           | mapping(uint256 => Prediction[])                | All predictions per matchId      |
| spectatorPredictions  | mapping(uint256 => mapping(address => uint256)) | Prediction index per spectator   |
| spectatorHasPredicted | mapping(uint256 => mapping(address => bool))    | Has spectator predicted?         |
| watcherCount          | mapping(uint256 => uint256)                     | Live watchers per matchId        |

================================================================

## FUNCTIONS

================================================================

### Constructor

constructor(address \_configContract)

- Sets owner = msg.sender
- Sets configContract = \_configContract

---

### Admin Functions (onlyOwner)

addAuthorizedMatch(address \_matchContract)

- Authorizes a CipherMatch contract to call restricted functions
- Emits: MatchAuthorized(address matchContract)

---

### Core Functions

initializePool(
uint256 \_matchId,
address \_playerA,
address \_playerB
)

- Called by CipherMatch.sol when match becomes ACTIVE
- Requires: msg.sender is authorized match contract
- Creates MatchPredictionPool for matchId
- Sets predictionsOpen = true
- Emits: PoolInitialized(uint256 matchId, address playerA, address playerB)

---

watchMatch(uint256 \_matchId)

- Called by spectator to register as watcher
- Requires: predictionPools[_matchId] exists
- Increments watcherCount[_matchId]
- Emits: SpectatorJoined(uint256 matchId, address spectator)

---

placePrediction(
uint256 \_matchId,
address \_chosenPlayer
) payable

- Called by spectator to place a prediction
- Requires: predictionPools[_matchId].predictionsOpen == true
- Requires: predictionPools[_matchId].resolved == false
- Requires: spectatorHasPredicted[\_matchId][msg.sender] == false
- Requires: msg.value > 0
- Requires: \_chosenPlayer == playerA or playerB for that match
- Requires: msg.sender is not playerA or playerB (players can't bet)

FLOW:

- Creates Prediction struct
- Adds to predictions[_matchId] array
- Updates poolForPlayerA or poolForPlayerB
- Updates totalPool
- Sets spectatorHasPredicted[\_matchId][msg.sender] = true
- Stores prediction index in spectatorPredictions
- Emits: PredictionPlaced(matchId, msg.sender, \_chosenPlayer, msg.value)

---

closePredictions(uint256 \_matchId)

- Called by CipherMatch.sol when final round starts
- Requires: msg.sender is authorized match contract
- Sets predictionPools[_matchId].predictionsOpen = false
- Emits: PredictionsClosed(uint256 matchId)

---

resolveMatch(uint256 \_matchId, address \_winner)

- Called by CipherMatch.sol when match concludes
- Requires: msg.sender is authorized match contract
- Requires: predictionPools[_matchId].resolved == false
- Sets winner in pool
- Sets resolved = true
- Calls \_distributePredictionPayouts(\_matchId, \_winner)
- Emits: MatchResolved(uint256 matchId, address winner)

---

\_distributePredictionPayouts(
uint256 \_matchId,
address \_winner
) internal

FLOW:

1. Get winning pool and losing pool amounts:
   If \_winner == playerA:
   winningPool = poolForPlayerA
   losingPool = poolForPlayerB
   Else:
   winningPool = poolForPlayerB
   losingPool = poolForPlayerA

2. If losingPool == 0:
   No incorrect predictors — refund all correct predictors
   their original stake back, no winnings
   Skip fee deduction

3. Calculate spectator fee:
   fee = (losingPool \* config.getSpectatorFeePercent()) / 100
   distributableLosingPool = losingPool - fee

4. Transfer fee to config.getTreasuryAddress()

5. For each prediction in predictions[_matchId]:
   If prediction.chosenPlayer == \_winner:
   spectatorShare = (prediction.amount \* distributableLosingPool)
   / winningPool
   payout = prediction.amount + spectatorShare
   Transfer payout to prediction.spectator
   Emit: PredictionPayout(matchId, spectator, payout)
   Else (wrong prediction):
   Tokens already in contract, distributed to winners
   Emit: PredictionLost(matchId, spectator, prediction.amount)

---

### View Functions (public)

getPool(uint256 \_matchId)
returns (MatchPredictionPool memory)

- Returns full pool data for a match

---

getPredictions(uint256 \_matchId)
returns (Prediction[] memory)

- Returns all predictions for a match

---

getSpectatorPrediction(uint256 \_matchId, address \_spectator)
returns (Prediction memory)

- Returns a specific spectator's prediction for a match

---

hasSpectatorPredicted(uint256 \_matchId, address \_spectator)
returns (bool)

- Returns true if spectator has already placed a prediction

---

getWatcherCount(uint256 \_matchId)
returns (uint256)

- Returns number of live watchers for a match

---

getPotentialReturn(uint256 \_matchId, address \_chosenPlayer, uint256 \_amount)
returns (uint256 estimatedPayout)

- Calculates estimated return if spectator bets \_amount on \_chosenPlayer
- Used by frontend to show "Potential return: X tokens"
- Formula:
  If \_chosenPlayer == playerA:
  opposingPool = poolForPlayerB
  Else:
  opposingPool = poolForPlayerA
  fee = (opposingPool _ spectatorFeePercent) / 100
  distributable = opposingPool - fee
  newWinningPool = poolForChosen + \_amount
  share = (\_amount _ distributable) / newWinningPool
  estimatedPayout = \_amount + share

---

getActiveMatchIds() returns (uint256[] memory)

- Returns all matchIds with open prediction pools

================================================================

## EVENTS

================================================================

event MatchAuthorized(address indexed matchContract)
event PoolInitialized(uint256 indexed matchId, address playerA, address playerB)
event SpectatorJoined(uint256 indexed matchId, address indexed spectator)
event PredictionPlaced(
uint256 indexed matchId,
address indexed spectator,
address chosenPlayer,
uint256 amount
)
event PredictionsClosed(uint256 indexed matchId)
event MatchResolved(uint256 indexed matchId, address indexed winner)
event PredictionPayout(
uint256 indexed matchId,
address indexed spectator,
uint256 payout
)
event PredictionLost(
uint256 indexed matchId,
address indexed spectator,
uint256 amount
)

================================================================

## ERRORS

================================================================

error NotOwner()
error NotAuthorizedMatch()
error PoolNotFound()
error PredictionsAreClosed()
error AlreadyPredicted()
error InvalidChosenPlayer()
error PlayersCannotPredict()
error ZeroStakeNotAllowed()
error PoolAlreadyResolved()
error InvalidAddress()

================================================================

## ACCESS CONTROL

================================================================

- initializePool(): only authorized CipherMatch contracts
- closePredictions(): only authorized CipherMatch contracts
- resolveMatch(): only authorized CipherMatch contracts
- watchMatch(): public, any wallet
- placePrediction(): public, any wallet except match players
- All view functions: public
- addAuthorizedMatch(): only owner

================================================================

## PAYOUT EXAMPLE

================================================================

Match #1042 — TOKEN MATCH
Players: PlayerA vs PlayerB
Winner: PlayerB

Spectator predictions:
Spectator 1 → PlayerA → 5 tokens (WRONG)
Spectator 2 → PlayerB → 5 tokens (CORRECT)
Spectator 3 → PlayerB → 10 tokens (CORRECT)
Spectator 4 → PlayerA → 5 tokens (WRONG)

Pools:
poolForPlayerA = 10 tokens (losing pool)
poolForPlayerB = 15 tokens (winning pool)
totalPool = 25 tokens

Fee (5% of losing pool):
fee = 10 \* 5 / 100 = 0.5 tokens → treasury
distributableLosingPool = 10 - 0.5 = 9.5 tokens

Payouts for correct predictors:
Spectator 2 (5 tokens bet):
share = (5 \* 9.5) / 15 = 3.17 tokens
payout = 5 + 3.17 = 8.17 tokens

Spectator 3 (10 tokens bet):
share = (10 \* 9.5) / 15 = 6.33 tokens
payout = 10 + 6.33 = 16.33 tokens

Total distributed: 8.17 + 16.33 + 0.5 = 25 tokens ✓

================================================================

## SECURITY NOTES

================================================================

- Players cannot bet on their own match
- Each spectator can only predict once per match
- Predictions lock before final round — no last-second bets
- All payouts automatic — no claim function needed
- Fee deducted only from losing pool, not winning pool
- If no losing pool: correct predictors get full refund
- Reentrancy guard on \_distributePredictionPayouts
- Only authorized CipherMatch contracts can resolve pools

================================================================
END OF SPEC — CipherSpectator.sol
================================================================
