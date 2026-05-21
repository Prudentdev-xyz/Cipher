# CipherMatchFactory.sol — Full Specification

# CIPHER Protocol | Milestone 0.2

## PURPOSE

CipherMatchFactory.sol is the entry point for all matches
in CIPHER. It handles session code pairing, deploys individual
CipherMatch contracts for each game, and maintains a registry
of all active and completed matches.

When two players enter the same session code, this contract
automatically pairs them and deploys a fresh CipherMatch.sol
instance for their game.

================================================================

## STRUCTS

================================================================

struct MatchRecord {
address matchAddress; // deployed CipherMatch contract
address playerA;
address playerB;
uint256 createdAt; // block timestamp
bool isActive; // true while match is running
}

struct PendingPlayer {
address playerAddress;
uint256 joinedAt; // block timestamp
}

================================================================

## STATE VARIABLES

================================================================

| Variable          | Type                              | Description                           |
| ----------------- | --------------------------------- | ------------------------------------- |
| owner             | address                           | Admin address                         |
| configContract    | address                           | CipherConfig.sol address              |
| rankingContract   | address                           | CipherRanking.sol address             |
| spectatorContract | address                           | CipherSpectator.sol address           |
| pendingPlayers    | mapping(bytes32 => PendingPlayer) | First player waiting per session code |
| activeMatches     | mapping(bytes32 => MatchRecord)   | Active match per hashed session code  |
| allMatches        | mapping(uint256 => MatchRecord)   | All matches by matchId                |
| matchCount        | uint256                           | Total matches ever created            |
| playerMatches     | mapping(address => uint256[])     | Match IDs per player address          |
| pendingTimeout    | uint256                           | Seconds before pending slot expires   |

## CONSTANTS

uint256 constant PENDING_TIMEOUT = 300; // 5 minutes

================================================================

## FUNCTIONS

================================================================

### Constructor

constructor(
address \_configContract,
address \_rankingContract,
address \_spectatorContract
)

- Sets owner = msg.sender
- Sets configContract, rankingContract, spectatorContract
- Sets pendingTimeout = 300 seconds (5 minutes)

---

### Core Functions

joinMatch(string memory \_sessionCode)

- Called by both players to enter a session code
- Hashes session code: bytes32 codeHash = keccak256(abi.encodePacked(\_sessionCode))
- Requires: msg.sender not already in a pending slot
- Requires: msg.sender not already in an active match

FLOW:
If no pending player for this codeHash: - Store msg.sender in pendingPlayers[codeHash] - Store joinedAt = block.timestamp - Emit: MatchPending(codeHash, msg.sender)

If pending player exists for this codeHash: - Requires: pending slot not expired (joinedAt + PENDING_TIMEOUT > block.timestamp) - Requires: msg.sender != pendingPlayers[codeHash].playerAddress (can't match yourself) - Calls \_deployMatch(pendingPlayers[codeHash].playerAddress, msg.sender, codeHash) - Deletes pendingPlayers[codeHash] - Emit: MatchCreated(codeHash, matchAddress, playerA, playerB)

---

\_deployMatch(
address \_playerA,
address \_playerB,
bytes32 \_codeHash
) internal

- Deploys new CipherMatch.sol instance with:
  playerA, playerB,
  configContract, rankingContract, spectatorContract,
  matchId = matchCount + 1
- Increments matchCount
- Stores MatchRecord in allMatches[matchId]
- Stores MatchRecord in activeMatches[codeHash]
- Adds matchId to playerMatches[playerA] and playerMatches[playerB]
- Emits: MatchDeployed(uint256 matchId, address matchAddress, address playerA, address playerB)

---

cancelPending(string memory \_sessionCode)

- Called by a player who is waiting and wants to cancel
- Hashes session code to get codeHash
- Requires: pendingPlayers[codeHash].playerAddress == msg.sender
- Deletes pendingPlayers[codeHash]
- Emits: MatchCancelled(bytes32 codeHash, address player)

---

cleanExpiredPending(string memory \_sessionCode)

- Called by anyone to clean up an expired pending slot
- Requires: pending slot exists AND joinedAt + PENDING_TIMEOUT < block.timestamp
- Deletes pendingPlayers[codeHash]
- Emits: PendingExpired(bytes32 codeHash)

---

markMatchInactive(uint256 \_matchId)

- Called by CipherMatch.sol when a match concludes or cancels
- Requires: msg.sender == allMatches[_matchId].matchAddress
- Sets allMatches[_matchId].isActive = false
- Removes from activeMatches mapping
- Emits: MatchInactive(uint256 matchId)

---

### View Functions (public)

getMatch(uint256 \_matchId)
returns (MatchRecord memory)

- Returns full MatchRecord for a given matchId

---

getActiveMatchByCode(string memory \_sessionCode)
returns (MatchRecord memory)

- Hashes session code and returns active match record
- Returns empty struct if no active match for that code

---

getPlayerMatches(address \_player)
returns (uint256[] memory)

- Returns all matchIds a player has participated in

---

getPendingPlayer(string memory \_sessionCode)
returns (address, uint256)

- Returns address and joinedAt of pending player for a code
- Returns (address(0), 0) if no pending player

---

getTotalMatchCount() returns (uint256)

- Returns total number of matches ever created

---

isPlayerInPending(address \_player) returns (bool)

- Returns true if a player is currently in any pending slot
- Prevents a player from entering multiple session codes

---

isMatchActive(uint256 \_matchId) returns (bool)

- Returns true if a match is currently active

================================================================

## EVENTS

================================================================

event MatchPending(
bytes32 indexed codeHash,
address indexed player
)
event MatchCreated(
bytes32 indexed codeHash,
address indexed matchAddress,
address indexed playerA,
address playerB
)
event MatchDeployed(
uint256 indexed matchId,
address indexed matchAddress,
address playerA,
address playerB
)
event MatchCancelled(
bytes32 indexed codeHash,
address indexed player
)
event PendingExpired(bytes32 indexed codeHash)
event MatchInactive(uint256 indexed matchId)

================================================================

## ERRORS

================================================================

error NotOwner()
error AlreadyInPending()
error AlreadyInActiveMatch()
error NoPendingPlayerFound()
error PendingSlotExpired()
error CannotMatchYourself()
error NotMatchContract()
error InvalidAddress()

================================================================

## ACCESS CONTROL

================================================================

- joinMatch(): public, any wallet
- cancelPending(): public, only the pending player themselves
- cleanExpiredPending(): public, anyone can clean expired slots
- markMatchInactive(): only the CipherMatch contract for that matchId
- All view functions: public
- Admin setters: onlyOwner

================================================================

## SECURITY NOTES

================================================================

- Session codes are hashed with keccak256 before storage
  (prevents front-running — attacker cannot see plaintext code)
- Players cannot match against themselves
- Pending slots expire after 5 minutes automatically
- A player cannot be in two pending slots simultaneously
- Only the deployed CipherMatch contract can mark itself inactive
- Factory does not hold any funds at any time

================================================================

## SESSION CODE HASHING

================================================================

The session code entered by the player (e.g. "CIPHER99") is
NEVER stored as plaintext onchain. It is always hashed first:

bytes32 codeHash = keccak256(abi.encodePacked(\_sessionCode))

This means:

- No one watching the mempool can see the session code
- No one can join a match they weren't invited to
- Two players with the same code will produce the same hash
  and be paired correctly

================================================================
END OF SPEC — CipherMatchFactory.sol
================================================================
