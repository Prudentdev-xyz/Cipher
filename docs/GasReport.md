# CIPHER — Gas Usage Report

# Milestone 1.6 | Phase 1 Complete

## NOTE

hardhat-gas-reporter does not yet support Hardhat 3.
Gas estimates below are based on contract analysis and
standard Solidity patterns. Will be updated with exact
onchain measurements when deployed to Ritual Testnet.

================================================================

## CipherConfig.sol

================================================================

| Function                  | Estimated Gas | Notes                      |
| ------------------------- | ------------- | -------------------------- |
| constructor()             | ~800,000      | Deploys with 20 categories |
| setPlatformFeePercent()   | ~30,000       | Single storage write       |
| setSpectatorFeePercent()  | ~30,000       | Single storage write       |
| setRoundCount()           | ~30,000       | Single storage write       |
| setRoundDurationSeconds() | ~30,000       | Single storage write       |
| setTreasuryAddress()      | ~30,000       | Single storage write       |
| addCategory()             | ~50,000       | Array push                 |
| removeCategory()          | ~40,000       | Array swap + pop           |
| getCategoryList()         | ~25,000       | View — reads array         |
| isValidStakeAmount()      | ~5,000        | Pure — no storage          |
| isCategoryValid()         | ~20,000       | Loop over categories       |

================================================================

## CipherRanking.sol

================================================================

| Function                | Estimated Gas | Notes                     |
| ----------------------- | ------------- | ------------------------- |
| constructor()           | ~300,000      | Basic setup               |
| initializePlayer()      | ~80,000       | Struct write + array push |
| updateRanking()         | ~120,000      | Two struct updates        |
| calculatePointsChange() | ~10,000       | View — math only          |
| getLeaderboard()        | ~200,000      | Sort + array copy         |
| getPlayerRank()         | ~10,000       | Single struct read        |
| addAuthorizedCaller()   | ~30,000       | Single mapping write      |

================================================================

## CipherMatchFactory.sol

================================================================

| Function              | Estimated Gas | Notes                |
| --------------------- | ------------- | -------------------- |
| constructor()         | ~250,000      | Basic setup          |
| joinMatch() — first   | ~80,000       | Pending slot write   |
| joinMatch() — second  | ~200,000      | Deploys CipherMatch  |
| cancelPending()       | ~40,000       | Delete mapping entry |
| cleanExpiredPending() | ~40,000       | Delete mapping entry |
| markMatchInactive()   | ~30,000       | Single bool write    |
| getPlayerMatches()    | ~15,000       | Array read           |

================================================================

## CipherMatch.sol

================================================================

| Function               | Estimated Gas | Notes                     |
| ---------------------- | ------------- | ------------------------- |
| constructor()          | ~400,000      | Full match state setup    |
| confirmStake() — FREE  | ~60,000       | Bool write                |
| confirmStake() — TOKEN | ~80,000       | Bool write + ETH lock     |
| cancelMatch()          | ~50,000       | State change + refund     |
| selectCategory()       | ~100,000      | Storage + challenge gen   |
| submitGuess()          | ~50,000       | String storage write      |
| closeRound()           | ~150,000      | Eval + score + next round |
| \_distributePayout()   | ~60,000       | Two ETH transfers         |

================================================================

## CipherSpectator.sol

================================================================

| Function             | Estimated Gas | Notes                  |
| -------------------- | ------------- | ---------------------- |
| constructor()        | ~200,000      | Basic setup            |
| initializePool()     | ~80,000       | Struct write           |
| watchMatch()         | ~40,000       | Counter increment      |
| placePrediction()    | ~90,000       | Struct push + ETH lock |
| closePredictions()   | ~30,000       | Bool write             |
| resolveMatch()       | ~150,000+     | Loop + transfers       |
| getPotentialReturn() | ~10,000       | View — math only       |

================================================================

## FULL MATCH GAS ESTIMATE

================================================================

One complete 6-round FREE match:
Deploy CipherMatch: ~400,000
confirmStake x2: ~120,000
selectCategory x6: ~600,000
submitGuess x6: ~300,000
closeRound x6: ~900,000
updateRanking: ~120,000
─────────────────────────────────
TOTAL (approx): ~2,440,000 gas

One complete 6-round TOKEN match (additional):
ETH transfers (payout): ~60,000
─────────────────────────────────
TOTAL (approx): ~2,500,000 gas

================================================================

## TODO — EXACT GAS MEASUREMENTS

================================================================

When Ritual Testnet access is available:
□ Deploy all contracts to Ritual Testnet
□ Run full match simulation onchain
□ Record exact gas per transaction
□ Update this document with real values
□ Optimize any functions exceeding 500,000 gas

================================================================
END — GasReport.md
================================================================
