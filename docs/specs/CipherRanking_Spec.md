# CipherRanking.sol — Full Specification
CIPHER Protocol | Milestone 0.2
================================================================

## PURPOSE
CipherRanking.sol stores and manages all player rankings
onchain. Every wallet that plays CIPHER gets a permanent
rank record tied to their address. Rankings update after
every match. The leaderboard is publicly queryable.

================================================================
## ENUMS
================================================================

```
enum Tier {
    NOVICE,        // 0 - 999 points
    SOLVER,        // 1,000 - 2,999 points
    DECODER,       // 3,000 - 5,999 points
    CRYPTIC,       // 6,000 - 9,999 points
    CIPHER_ELITE   // 10,000+ points
}
```

================================================================
## STRUCTS
================================================================

```
struct RankData {
    uint256 totalPoints;
    Tier tier;
    uint256 wins;
    uint256 losses;
    uint256 totalMatches;
    uint256 tokensEarned;
    bool initialized;
}
```

================================================================
## STATE VARIABLES
================================================================

| Variable              | Type                          | Description                        |
|----------------------|-------------------------------|------------------------------------|
| playerRankings       | mapping(address => RankData)  | Rank data per wallet address       |
| rankedPlayers        | address[]                     | Array of all ranked player addresses|
| authorizedCallers    | mapping(address => bool)      | Contracts allowed to update ranks  |
| owner                | address                       | Admin address                      |
| configContract       | address                       | CipherConfig.sol address           |

## TIER THRESHOLDS (constants)

```
uint256 constant SOLVER_THRESHOLD       = 1000;
uint256 constant DECODER_THRESHOLD      = 3000;
uint256 constant CRYPTIC_THRESHOLD      = 6000;
uint256 constant CIPHER_ELITE_THRESHOLD = 10000;
```

## POINTS CONSTANTS

```
uint256 constant BASE_WIN_POINTS        = 100;
uint256 constant BASE_LOSS_POINTS       = 80;
uint256 constant TOKEN_MATCH_BONUS_PCT  = 20;
```

================================================================
## FUNCTIONS
================================================================

### Constructor
```
constructor(address _configContract)
```
- Sets owner = msg.sender
- Sets configContract = _configContract
- Authorizes owner as caller initially

---

### Admin Functions (onlyOwner)

```
addAuthorizedCaller(address _caller)
```
- Adds a CipherMatch contract address as authorized caller
- Only CipherMatch.sol should call updateRanking()
- Emits: CallerAuthorized(address caller)

---

```
removeAuthorizedCaller(address _caller)
```
- Removes an authorized caller
- Emits: CallerRemoved(address caller)

---

### Core Functions

```
initializePlayer(address _player)
```
- Called automatically on first match
- Creates RankData entry with:
    totalPoints = 0
    tier = Tier.NOVICE
    wins = 0, losses = 0
    totalMatches = 0
    tokensEarned = 0
    initialized = true
- Adds player to rankedPlayers array
- Reverts if already initialized
- Emits: PlayerInitialized(address player)

---

```
updateRanking(
    address _winner,
    address _loser,
    uint256 _stakeMode,
    uint256 _tokensWon
)
```
- RESTRICTED: only authorized callers (CipherMatch.sol)
- Initializes players if not already initialized
- Calls calculatePointsChange() internally
- Updates winner: totalPoints += winPoints, wins++
- Updates loser: totalPoints -= lossPoints (floor at 0), losses++
- Updates totalMatches for both
- Updates tokensEarned for winner
- Calls _updateTier() for both players
- Emits: RankingUpdated(address winner, address loser,
          uint256 winPoints, uint256 lossPoints)

---

```
calculatePointsChange(
    address _winner,
    address _loser,
    uint256 _stakeMode
) internal view returns (uint256 winPoints, uint256 lossPoints)
```
- Internal function
- Gets winner and loser tier
- Calculates tier difference bonus/mitigation:

    If winner tier < loser tier (upset):
        winPoints = BASE_WIN_POINTS + (tierDiff * 40)
        lossPoints = BASE_LOSS_POINTS + (tierDiff * 30)

    If winner tier > loser tier (expected win):
        winPoints = BASE_WIN_POINTS - (tierDiff * 25)
        lossPoints = BASE_LOSS_POINTS - (tierDiff * 20)

    If same tier:
        winPoints = BASE_WIN_POINTS
        lossPoints = BASE_LOSS_POINTS

- If stakeMode == 1 (Token Match):
    Apply +20% bonus to both winPoints and lossPoints

- Examples:
    NOVICE beats NOVICE    → +100 win, -80 loss
    NOVICE beats DECODER   → +180 win, -140 loss
    DECODER beats NOVICE   → +50 win,  -40 loss
    CRYPTIC beats NOVICE   → +25 win,  -20 loss
    Token Match multiplier → all values +20%

---

```
_updateTier(address _player) internal
```
- Called after every ranking update
- Reads player totalPoints
- Sets tier based on thresholds:
    0–999       → NOVICE
    1000–2999   → SOLVER
    3000–5999   → DECODER
    6000–9999   → CRYPTIC
    10000+      → CIPHER_ELITE
- Emits TierChanged event if tier changed

---

### View Functions (public)

```
getPlayerRank(address _player)
    returns (RankData memory)
```
- Returns full RankData struct for a player
- Returns empty/default struct if not initialized

---

```
getPlayerTier(address _player)
    returns (Tier)
```
- Returns current tier of a player

---

```
getPlayerPoints(address _player)
    returns (uint256)
```
- Returns total points of a player

---

```
getLeaderboard(uint256 _limit)
    returns (address[] memory, RankData[] memory)
```
- Returns top _limit players sorted by totalPoints
- Sorts rankedPlayers array by points (descending)
- Returns parallel arrays: addresses + their RankData
- Max _limit = 100

---

```
getLeaderboardByTier(Tier _tier, uint256 _limit)
    returns (address[] memory, RankData[] memory)
```
- Returns top _limit players within a specific tier
- Filters rankedPlayers by tier first, then sorts

---

```
getTotalPlayers() returns (uint256)
```
- Returns total number of ranked players

---

```
isInitialized(address _player) returns (bool)
```
- Returns whether a player has been initialized

---

```
getTierThreshold(Tier _tier) returns (uint256)
```
- Returns the point threshold for a given tier

================================================================
## EVENTS
================================================================

```
event PlayerInitialized(address indexed player)
event RankingUpdated(
    address indexed winner,
    address indexed loser,
    uint256 winPoints,
    uint256 lossPoints
)
event TierChanged(
    address indexed player,
    Tier oldTier,
    Tier newTier
)
event CallerAuthorized(address indexed caller)
event CallerRemoved(address indexed caller)
```

================================================================
## ERRORS
================================================================

```
error NotOwner()
error NotAuthorizedCaller()
error PlayerAlreadyInitialized(address player)
error InvalidAddress()
error LeaderboardLimitTooHigh(uint256 provided, uint256 max)
```

================================================================
## ACCESS CONTROL
================================================================

- updateRanking(): only authorized callers (CipherMatch.sol)
- initializePlayer(): only authorized callers
- addAuthorizedCaller(): only owner
- All view functions: public, no restriction

================================================================
## SECURITY NOTES
================================================================

- Points floor at 0 — players cannot go negative
- Only CipherMatch.sol can update rankings (not players)
- Tier changes are automatic and cannot be manually set
- Rankings are permanent and cannot be deleted by anyone
- Leaderboard is read-only — no manipulation possible

================================================================
END OF SPEC — CipherRanking.sol
================================================================