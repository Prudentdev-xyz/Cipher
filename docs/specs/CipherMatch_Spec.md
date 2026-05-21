# CipherMatch.sol — Full Specification

# CIPHER Protocol | Milestone 0.2

## PURPOSE

CipherMatch.sol is the core game contract. One instance is
deployed per match by CipherMatchFactory.sol. It manages the
entire lifecycle of a single match: stake confirmation, round
state, Ritual AI challenge generation, TEE secret word storage,
autonomous timer, guess evaluation, score tracking, winner
determination, payout distribution, and cancellation.

================================================================

## ENUMS

================================================================

enum StakeMode {
FREE, // 0 - no tokens, ranking points only
TOKEN // 1 - testnet tokens staked
}

enum MatchState {
PENDING_STAKE, // waiting for both players to confirm stake
ACTIVE, // match is running
CONCLUDED, // match finished normally
CANCELLED // match cancelled, refunds issued
}

enum RoundState {
PENDING_CATEGORY, // waiting for Presenter to pick category
PENDING_GUESS, // challenge generated, waiting for guess
CLOSED // round timer fired, round evaluated
}

================================================================

## STRUCTS

================================================================

struct RoundData {
uint256 roundNumber;
address presenter;
address guesser;
string category;
string riddle;
string sketchDescription;
bytes32 encryptedSecretWord; // TEE reference, never plaintext
string guess;
bool isCorrect;
RoundState state;
uint256 startedAt; // block timestamp when round started
}

struct StakeData {
StakeMode mode;
uint256 amount; // per player stake amount
bool playerAConfirmed;
bool playerBConfirmed;
uint256 confirmDeadline; // timestamp deadline for confirmation
}

================================================================

## STATE VARIABLES

================================================================

| Variable          | Type        | Description                        |
| ----------------- | ----------- | ---------------------------------- |
| matchId           | uint256     | Unique match ID from factory       |
| playerA           | address     | First player address               |
| playerB           | address     | Second player address              |
| stakeData         | StakeData   | Stake mode and confirmation state  |
| matchState        | MatchState  | Current state of the match         |
| rounds            | RoundData[] | Array of all rounds played         |
| currentRound      | uint256     | Current round number (1-based)     |
| scoreA            | uint256     | Player A correct guesses           |
| scoreB            | uint256     | Player B correct guesses           |
| winner            | address     | Winner address (set on conclusion) |
| isTiebreaker      | bool        | True if match went to tiebreaker   |
| configContract    | address     | CipherConfig.sol address           |
| rankingContract   | address     | CipherRanking.sol address          |
| spectatorContract | address     | CipherSpectator.sol address        |
| factoryContract   | address     | CipherMatchFactory.sol address     |

================================================================

## FUNCTIONS

================================================================

### Constructor

constructor(
uint256 \_matchId,
address \_playerA,
address \_playerB,
address \_configContract,
address \_rankingContract,
address \_spectatorContract,
address \_factoryContract
)

- Sets all addresses and matchId
- Sets matchState = PENDING_STAKE
- Sets stakeData.confirmDeadline =
  block.timestamp + config.getStakeTimeoutSeconds()
- Emits: MatchInitialized(matchId, playerA, playerB)

---

### Stake Functions

confirmStake(StakeMode \_mode, uint256 \_amount) payable

- Called by each player to confirm their stake
- Requires: matchState == PENDING_STAKE
- Requires: msg.sender == playerA or playerB
- Requires: block.timestamp < stakeData.confirmDeadline
- If FREE mode: \_amount must be 0, no ETH sent
- If TOKEN mode:
  Requires: config.isValidStakeAmount(\_amount) == true
  Requires: msg.value == \_amount
- On first confirmation: stores mode and amount
- On second confirmation:
  Requires: mode matches first player's mode
  Requires: amount matches first player's amount
  Calls \_startMatch()
- Emits: StakeConfirmed(address player, StakeMode mode, uint256 amount)

---

\_startMatch() internal

- Sets matchState = ACTIVE
- Sets currentRound = 1
- Assigns roles for Round 1:
  Presenter = playerA (determined by address comparison)
  Guesser = playerB
- Initializes first RoundData in rounds array
- Emits: MatchStarted(matchId, playerA, playerB)

---

cancelMatch()

- Callable by either player OR automatically on timeout
- Requires: matchState == PENDING_STAKE OR
  (matchState == ACTIVE and opponent disconnected)
- If TOKEN mode and funds deposited: refunds each player
- Sets matchState = CANCELLED
- Calls factoryContract.markMatchInactive(matchId)
- Emits: MatchCancelled(matchId, string reason)

---

### Round Functions

selectCategory(string memory \_category)

- Called by the Presenter for the current round
- Requires: matchState == ACTIVE
- Requires: msg.sender == current round's presenter
- Requires: current round state == PENDING_CATEGORY
- Requires: \_category is valid (exists in config.getCategoryList())
- Stores category in current RoundData
- Calls \_generateChallenge(\_category)
- Emits: CategorySelected(matchId, currentRound, \_category)

---

\_generateChallenge(string memory \_category) internal

- Makes native Ritual AI precompile call:

  INPUT:
  {
  model: "ritual-llm-v1",
  prompt: "Generate a secret word, riddle, and visual
  description for category: [_category].
  Return JSON: secret_word, riddle,
  sketch_description.
  secret_word: single common noun.
  riddle: strong clues, don't name the word.
  sketch_description: simple visual under 20 words.",
  confidential: true,
  max_tokens: 200
  }

  OUTPUT (from Ritual):
  - secret_word → stored in TEE (encrypted, never public)
  - riddle → stored in rounds[currentRound].riddle
  - sketch_description → stored in rounds[currentRound].sketchDescription

- Sets encryptedSecretWord = TEE reference returned by Ritual
- Sets round state = PENDING_GUESS
- Registers 30-second timer with Ritual Autonomous Scheduler:
  callback: closeRound(currentRound)
  delay: config.getRoundDurationSeconds()
- Emits: ChallengeGenerated(matchId, currentRound, riddle, sketchDescription)

---

submitGuess(string memory \_guess)

- Called by the Guesser during the 30-second window
- Requires: matchState == ACTIVE
- Requires: msg.sender == current round's guesser
- Requires: round state == PENDING_GUESS
- Requires: round not already closed
- Stores guess in rounds[currentRound].guess
- Emits: GuessSubmitted(matchId, currentRound, msg.sender)

---

closeRound(uint256 \_roundNumber)

- Called AUTOMATICALLY by Ritual Autonomous Scheduler at 30s
- Can also be called manually if timer already passed (fallback)
- Requires: matchState == ACTIVE
- Requires: rounds[_roundNumber].state == PENDING_GUESS

FLOW:

1. Decrypts secret word from TEE via Ritual
2. Stores plaintext secret word in rounds[_roundNumber] (now revealed)
3. Evaluates guess:
   - Converts both guess and secret_word to lowercase
   - If match: isCorrect = true, increment winner's score
   - If no guess submitted: isCorrect = false
4. Sets round state = CLOSED
5. Emits: RoundClosed(matchId, roundNumber, secretWord, guess, isCorrect)
6. Checks if match should continue:
   - If currentRound < config.getRoundCount(): calls \_startNextRound()
   - If currentRound == config.getRoundCount(): calls \_concludeMatch()

---

\_startNextRound() internal

- Increments currentRound
- Swaps roles: previous Guesser becomes Presenter, vice versa
- Initializes new RoundData entry
- Sets new round state = PENDING_CATEGORY
- Emits: RoundStarted(matchId, currentRound, presenter, guesser)

---

### Match Conclusion

\_concludeMatch() internal

- Called after all rounds complete

FLOW:

1. Compare scoreA and scoreB
2. If scoreA > scoreB: winner = playerA
3. If scoreB > scoreA: winner = playerB
4. If scoreA == scoreB: calls \_startTiebreakerRound()
5. If winner determined:
   - Calls \_distributePayout()
   - Calls rankingContract.updateRanking(winner, loser, stakeMode, tokensWon)
   - Calls spectatorContract.resolveMatch(matchId, winner)
   - Calls factoryContract.markMatchInactive(matchId)
   - Sets matchState = CONCLUDED
   - Emits: MatchConcluded(matchId, winner, scoreA, scoreB)

---

\_startTiebreakerRound() internal

- Sets isTiebreaker = true
- Increments currentRound
- Assigns roles for tiebreaker (alternates from last round)
- Initializes new RoundData
- Emits: TiebreakerStarted(matchId, currentRound)
- Note: tiebreaker runs exactly like a normal round
  After tiebreaker closes, \_concludeMatch() is called again
  If still tied after tiebreaker: another tiebreaker fires

---

\_distributePayout() internal

- Only runs if stakeMode == TOKEN
- Calculates total pot: stakeData.amount \* 2
- Calculates platform fee:
  fee = (totalPot \* config.getPlatformFeePercent()) / 100
- Calculates winner payout:
  payout = totalPot - fee
- Transfers payout to winner address
- Transfers fee to config.getTreasuryAddress()
- Emits: PayoutDistributed(matchId, winner, payout, fee)

---

### View Functions

getMatchState() returns (MatchState)
getScore() returns (uint256 scoreA, uint256 scoreB)
getCurrentRound() returns (uint256)
getRoundData(uint256 \_roundNumber) returns (RoundData memory)
getWinner() returns (address)
getPlayers() returns (address playerA, address playerB)
getStakeData() returns (StakeData memory)
isPlayerInMatch(address \_player) returns (bool)

================================================================

## EVENTS

================================================================

event MatchInitialized(uint256 indexed matchId, address playerA, address playerB)
event StakeConfirmed(address indexed player, StakeMode mode, uint256 amount)
event MatchStarted(uint256 indexed matchId, address playerA, address playerB)
event CategorySelected(uint256 indexed matchId, uint256 round, string category)
event ChallengeGenerated(uint256 indexed matchId, uint256 round, string riddle, string sketchDescription)
event GuessSubmitted(uint256 indexed matchId, uint256 round, address guesser)
event RoundClosed(uint256 indexed matchId, uint256 round, string secretWord, string guess, bool correct)
event RoundStarted(uint256 indexed matchId, uint256 round, address presenter, address guesser)
event TiebreakerStarted(uint256 indexed matchId, uint256 round)
event MatchConcluded(uint256 indexed matchId, address winner, uint256 scoreA, uint256 scoreB)
event PayoutDistributed(uint256 indexed matchId, address winner, uint256 payout, uint256 fee)
event MatchCancelled(uint256 indexed matchId, string reason)

================================================================

## ERRORS

================================================================

error NotAPlayer()
error NotPresenter()
error NotGuesser()
error MatchNotActive()
error MatchNotPending()
error StakeAlreadyConfirmed()
error StakeModeMismatch()
error StakeAmountMismatch()
error StakeTimeoutReached()
error InvalidStakeAmount()
error InvalidCategory()
error RoundNotOpen()
error RoundAlreadyClosed()
error AlreadySubmittedGuess()
error NotScheduler()

================================================================

## ACCESS CONTROL

================================================================

- confirmStake(): only playerA or playerB
- selectCategory(): only current round's Presenter
- submitGuess(): only current round's Guesser
- closeRound(): only Ritual Autonomous Scheduler
- \_generateChallenge(): internal only
- \_startMatch(): internal only
- \_concludeMatch(): internal only
- \_distributePayout(): internal only
- All view functions: public

================================================================

## RITUAL INTEGRATION NOTES

================================================================

AI PRECOMPILE:

- Called inside \_generateChallenge()
- confidential: true ensures secret_word goes to TEE
- riddle and sketchDescription returned as public output
- Model: ritual-llm-v1

TEE SECRET WORD STORAGE:

- secret_word NEVER stored in public contract state
- Stored as encrypted reference: encryptedSecretWord (bytes32)
- Only Ritual execution environment can decrypt it
- Decrypted only inside closeRound() at round end
- After reveal: plaintext stored in RoundData for both players

AUTONOMOUS SCHEDULER:

- Registered inside \_generateChallenge()
- Fires closeRound(\_roundNumber) after 30 seconds
- No keeper bot needed
- No human transaction needed to close rounds

================================================================

## SECURITY NOTES

================================================================

- Secret word never in public state until round ends
- Escrow funds cannot be locked: cancellation always refunds
- Only scheduler can call closeRound (no early forced close)
- Players cannot submit guess after round closes
- Payout math verified: fee + winner payout = total pot exactly
- Reentrancy guard on all payout functions
- Players cannot join their own match or call opponent functions

================================================================
END OF SPEC — CipherMatch.sol
================================================================
