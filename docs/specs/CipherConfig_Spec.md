# CipherConfig.sol — Full Specification

# CIPHER Protocol | Milestone 0.2

## PURPOSE

CipherConfig.sol stores all protocol-level parameters for the
CIPHER game. It is the single source of truth for fees, round
settings, stake limits, category list, and treasury address.
All other contracts read from CipherConfig.sol.

================================================================

## STATE VARIABLES

================================================================

| Variable             | Type     | Default     | Description                         |
| -------------------- | -------- | ----------- | ----------------------------------- |
| platformFeePercent   | uint256  | 5           | % fee taken from match winnings     |
| spectatorFeePercent  | uint256  | 5           | % fee taken from spectator winnings |
| roundCount           | uint256  | 6           | Number of rounds per match          |
| roundDurationSeconds | uint256  | 30          | Duration of each round in seconds   |
| stakeTimeoutSeconds  | uint256  | 120         | Timeout for stake confirmation      |
| minStakeAmount       | uint256  | 0.01 RITUAL | Minimum stake per player            |
| maxStakeAmount       | uint256  | 0.05 RITUAL | Maximum stake per player            |
| treasuryAddress      | address  | -           | Address that receives protocol fees |
| owner                | address  | -           | Admin address (set on deploy)       |
| categoryList         | string[] | -           | Array of 20 game categories         |

================================================================

## STAKE AMOUNTS (Testnet)

================================================================

Stake Mode: FREE
Amount: 0 RITUAL
Description: No tokens required, ranking points only

Stake Mode: TOKEN MATCH
Allowed amounts (player picks one):
0.01 RITUAL <- minimum
0.02 RITUAL
0.03 RITUAL
0.04 RITUAL
0.05 RITUAL <- maximum

Both players must pick the same amount.
Amounts stored in wei:
0.01 RITUAL = 10000000000000000 (1e16)
0.02 RITUAL = 20000000000000000 (2e16)
0.03 RITUAL = 30000000000000000 (3e16)
0.04 RITUAL = 40000000000000000 (4e16)
0.05 RITUAL = 50000000000000000 (5e16)

On Mainnet (Phase 5):
Min and max updated via governance.
Same 5-tier selection UI applies.

================================================================

## CATEGORIES (Full Set — 20 Categories)

================================================================

Index 0: "Science"
Index 1: "Nature"
Index 2: "Technology"
Index 3: "Objects"
Index 4: "Pop Culture"
Index 5: "History"
Index 6: "Geography"
Index 7: "Sports"
Index 8: "Food & Drink"
Index 9: "Entertainment"
Index 10: "Animals"
Index 11: "Movies & TV"
Index 12: "Music"
Index 13: "Fashion"
Index 14: "Space"
Index 15: "Human Body"
Index 16: "Mythology"
Index 17: "Cars & Vehicles"
Index 18: "Web3 & Crypto"
Index 19: "Artificial Intelligence"

Notes:

- "Technology" covers general tech: computers, internet, gadgets
- "Web3 & Crypto" covers: blockchain, NFTs, DeFi, wallets, protocols
- "Artificial Intelligence" covers: AI models, robotics, machine learning
- Categories expandable via owner governance at any time
- Dynamic categories via Ritual Internet Access planned for Phase 4

================================================================

## FUNCTIONS

================================================================

### Constructor

constructor(address \_treasuryAddress)

- Sets owner = msg.sender
- Sets treasuryAddress = \_treasuryAddress
- Sets all default values
- Sets minStakeAmount = 0.01 RITUAL (1e16)
- Sets maxStakeAmount = 0.05 RITUAL (5e16)
- Populates categoryList with all 20 categories

---

### Setter Functions (onlyOwner)

setPlatformFeePercent(uint256 \_fee)

- Requires: \_fee <= 20 (max 20%)
- Emits: FeeUpdated(string feeType, uint256 newFee)

setSpectatorFeePercent(uint256 \_fee)

- Requires: \_fee <= 20
- Emits: FeeUpdated(string feeType, uint256 newFee)

setRoundCount(uint256 \_count)

- Requires: \_count >= 2 && \_count <= 20
- Emits: ConfigUpdated(string param, uint256 newValue)

setRoundDurationSeconds(uint256 \_duration)

- Requires: \_duration >= 15 && \_duration <= 120
- Emits: ConfigUpdated(string param, uint256 newValue)

setStakeTimeoutSeconds(uint256 \_timeout)

- Requires: \_timeout >= 60
- Emits: ConfigUpdated(string param, uint256 newValue)

setMinStakeAmount(uint256 \_amount)

- Requires: \_amount < maxStakeAmount
- Emits: ConfigUpdated(string param, uint256 newValue)

setMaxStakeAmount(uint256 \_amount)

- Requires: \_amount > minStakeAmount
- Emits: ConfigUpdated(string param, uint256 newValue)

setTreasuryAddress(address \_treasury)

- Requires: \_treasury != address(0)
- Emits: TreasuryUpdated(address newTreasury)

addCategory(string memory \_category)

- Adds new category to categoryList
- Emits: CategoryAdded(string category)

removeCategory(uint256 \_index)

- Requires: categoryList.length > 1
- Removes category at given index
- Emits: CategoryRemoved(uint256 index)

---

### Getter Functions (public view)

getPlatformFeePercent() returns (uint256)
getSpectatorFeePercent() returns (uint256)
getRoundCount() returns (uint256)
getRoundDurationSeconds() returns (uint256)
getStakeTimeoutSeconds() returns (uint256)
getMinStakeAmount() returns (uint256)
getMaxStakeAmount() returns (uint256)
getTreasuryAddress() returns (address)
getCategoryList() returns (string[] memory)
getCategoryAt(uint256 index) returns (string memory)
getCategoryCount() returns (uint256)

isValidStakeAmount(uint256 \_amount) returns (bool)

- Returns true only for: 1e16, 2e16, 3e16, 4e16, 5e16
- Returns false for any other amount including 0
- Used by CipherMatch.sol to validate stake on confirmation

================================================================

## EVENTS

================================================================

event FeeUpdated(string feeType, uint256 newFee)
event ConfigUpdated(string param, uint256 newValue)
event TreasuryUpdated(address newTreasury)
event CategoryAdded(string category)
event CategoryRemoved(uint256 index)

================================================================

## ERRORS

================================================================

error NotOwner()
error InvalidFeePercent(uint256 provided, uint256 max)
error InvalidRoundCount(uint256 provided)
error InvalidDuration(uint256 provided)
error InvalidAddress()
error CategoryListTooSmall()
error InvalidStakeRange()

================================================================

## ACCESS CONTROL

================================================================

- All setter functions: onlyOwner modifier
- All getter functions: public, no restriction
- Owner transfers via transferOwnership(address)
- Future: transition to community governance via multisig

================================================================

## SECURITY NOTES

================================================================

- Fee caps (max 20%) prevent owner from draining winnings
- Treasury address cannot be set to zero address
- Category list cannot be fully emptied
- Stake amounts validated against allowed tiers only
- Max stake capped at 0.05 RITUAL on testnet

================================================================
END OF SPEC — CipherConfig.sol (Final)
================================================================
