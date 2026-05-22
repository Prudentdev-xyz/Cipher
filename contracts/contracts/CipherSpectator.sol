// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICipherConfig {
    function getSpectatorFeePercent() external view returns (uint256);
    function getTreasuryAddress() external view returns (address);
}

/// @title CipherSpectator
/// @notice Manages spectator predictions and payouts for CIPHER matches
contract CipherSpectator {

    // ================================================================
    // STRUCTS
    // ================================================================

    struct Prediction {
        address spectator;
        address chosenPlayer;
        uint256 amount;
    }

    struct MatchPool {
        address playerA;
        address playerB;
        uint256 poolForPlayerA;
        uint256 poolForPlayerB;
        uint256 totalPool;
        bool predictionsOpen;
        bool resolved;
        address winner;
        uint256 spectatorCount;
    }

    // ================================================================
    // STATE VARIABLES
    // ================================================================

    address public owner;
    address public configContract;

    mapping(address => bool) public authorizedMatches;
    mapping(uint256 => MatchPool) public matchPools;
    mapping(uint256 => Prediction[]) public predictions;
    mapping(uint256 => mapping(address => bool)) public hasPredicted;
    mapping(uint256 => uint256) public watcherCount;

    // ================================================================
    // EVENTS
    // ================================================================

    event PoolInitialized(uint256 indexed matchId, address playerA, address playerB);
    event SpectatorJoined(uint256 indexed matchId, address indexed spectator);
    event PredictionPlaced(uint256 indexed matchId, address indexed spectator, address chosenPlayer, uint256 amount);
    event PredictionsLocked(uint256 indexed matchId);
    event PredictionResolved(uint256 indexed matchId, address indexed spectator, uint256 payout);
    event PredictionLost(uint256 indexed matchId, address indexed spectator, uint256 amount);
    event MatchAuthorized(address indexed matchContract);

    // ================================================================
    // ERRORS
    // ================================================================

    error NotOwner();
    error NotAuthorizedMatch();
    error PoolNotFound();
    error PredictionsAreClosed();
    error AlreadyPredicted();
    error InvalidChosenPlayer();
    error PlayersCannotPredict();
    error ZeroStakeNotAllowed();
    error PoolAlreadyResolved();
    error InvalidAddress();

    // ================================================================
    // MODIFIERS
    // ================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAuthorizedMatch() {
        if (!authorizedMatches[msg.sender]) revert NotAuthorizedMatch();
        _;
    }

    // ================================================================
    // CONSTRUCTOR
    // ================================================================

    constructor(address _configContract) {
        if (_configContract == address(0)) revert InvalidAddress();
        owner = _configContract != address(0) ? msg.sender : address(0);
        configContract = _configContract;
    }

    // ================================================================
    // ADMIN
    // ================================================================

    function addAuthorizedMatch(address _matchContract) external onlyOwner {
        if (_matchContract == address(0)) revert InvalidAddress();
        authorizedMatches[_matchContract] = true;
        emit MatchAuthorized(_matchContract);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();
        owner = _newOwner;
    }

    // ================================================================
    // CALLED BY CipherMatch.sol
    // ================================================================

    /// @notice Initialize prediction pool when match goes ACTIVE
    function initializePool(
        uint256 _matchId,
        address _playerA,
        address _playerB
    ) external onlyAuthorizedMatch {
        matchPools[_matchId] = MatchPool({
            playerA:          _playerA,
            playerB:          _playerB,
            poolForPlayerA:   0,
            poolForPlayerB:   0,
            totalPool:        0,
            predictionsOpen:  true,
            resolved:         false,
            winner:           address(0),
            spectatorCount:   0
        });
        emit PoolInitialized(_matchId, _playerA, _playerB);
    }

    /// @notice Lock predictions when final round starts
    function closePredictions(uint256 _matchId) external onlyAuthorizedMatch {
        matchPools[_matchId].predictionsOpen = false;
        emit PredictionsLocked(_matchId);
    }

    /// @notice Resolve match and distribute payouts
    function resolveMatch(
        uint256 _matchId,
        address _winner
    ) external onlyAuthorizedMatch {
        MatchPool storage pool = matchPools[_matchId];
        if (pool.resolved) revert PoolAlreadyResolved();

        pool.winner   = _winner;
        pool.resolved = true;

        _distributePredictionPayouts(_matchId, _winner);
    }

    // ================================================================
    // SPECTATOR FUNCTIONS
    // ================================================================

    /// @notice Register as a watcher for a match
    function watchMatch(uint256 _matchId) external {
        MatchPool storage pool = matchPools[_matchId];
        if (pool.playerA == address(0)) revert PoolNotFound();
        watcherCount[_matchId] += 1;
        emit SpectatorJoined(_matchId, msg.sender);
    }

    /// @notice Place a prediction on a match
    function placePrediction(
        uint256 _matchId,
        address _chosenPlayer
    ) external payable {
        MatchPool storage pool = matchPools[_matchId];
        if (pool.playerA == address(0)) revert PoolNotFound();
        if (!pool.predictionsOpen) revert PredictionsAreClosed();
        if (pool.resolved) revert PoolAlreadyResolved();
        if (hasPredicted[_matchId][msg.sender]) revert AlreadyPredicted();
        if (msg.value == 0) revert ZeroStakeNotAllowed();
        if (msg.sender == pool.playerA || msg.sender == pool.playerB)
            revert PlayersCannotPredict();
        if (_chosenPlayer != pool.playerA && _chosenPlayer != pool.playerB)
            revert InvalidChosenPlayer();

        predictions[_matchId].push(Prediction({
            spectator:    msg.sender,
            chosenPlayer: _chosenPlayer,
            amount:       msg.value
        }));

        hasPredicted[_matchId][msg.sender] = true;

        if (_chosenPlayer == pool.playerA) {
            pool.poolForPlayerA += msg.value;
        } else {
            pool.poolForPlayerB += msg.value;
        }

        pool.totalPool      += msg.value;
        pool.spectatorCount += 1;

        emit PredictionPlaced(_matchId, msg.sender, _chosenPlayer, msg.value);
    }

    // ================================================================
    // INTERNAL — PAYOUT DISTRIBUTION
    // ================================================================

    function _distributePredictionPayouts(
        uint256 _matchId,
        address _winner
    ) internal {
        MatchPool storage pool = matchPools[_matchId];
        Prediction[] storage preds = predictions[_matchId];

        if (preds.length == 0) return;

        uint256 winningPool = (_winner == pool.playerA)
            ? pool.poolForPlayerA
            : pool.poolForPlayerB;

        uint256 losingPool = (_winner == pool.playerA)
            ? pool.poolForPlayerB
            : pool.poolForPlayerA;

        // No losing pool — refund correct predictors
        if (losingPool == 0) {
            for (uint256 i = 0; i < preds.length; i++) {
                if (preds[i].chosenPlayer == _winner) {
                    payable(preds[i].spectator).transfer(preds[i].amount);
                    emit PredictionResolved(_matchId, preds[i].spectator, preds[i].amount);
                }
            }
            return;
        }

        // Deduct spectator fee from losing pool
        uint256 feePercent = ICipherConfig(configContract).getSpectatorFeePercent();
        uint256 fee = (losingPool * feePercent) / 100;
        uint256 distributable = losingPool - fee;

        // Send fee to treasury
        address treasury = ICipherConfig(configContract).getTreasuryAddress();
        payable(treasury).transfer(fee);

        // Distribute to correct predictors
        for (uint256 i = 0; i < preds.length; i++) {
            if (preds[i].chosenPlayer == _winner) {
                uint256 share = (preds[i].amount * distributable) / winningPool;
                uint256 payout = preds[i].amount + share;
                payable(preds[i].spectator).transfer(payout);
                emit PredictionResolved(_matchId, preds[i].spectator, payout);
            } else {
                emit PredictionLost(_matchId, preds[i].spectator, preds[i].amount);
            }
        }
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getPool(uint256 _matchId)
        external view returns (MatchPool memory)
    {
        return matchPools[_matchId];
    }

    function getPredictions(uint256 _matchId)
        external view returns (Prediction[] memory)
    {
        return predictions[_matchId];
    }

    function getSpectatorCount(uint256 _matchId)
        external view returns (uint256)
    {
        return matchPools[_matchId].spectatorCount;
    }

    function getPredictionPool(uint256 _matchId)
        external view returns (uint256)
    {
        return matchPools[_matchId].totalPool;
    }

    function hasSpectatorPredicted(uint256 _matchId, address _spectator)
        external view returns (bool)
    {
        return hasPredicted[_matchId][_spectator];
    }

    function getWatcherCount(uint256 _matchId)
        external view returns (uint256)
    {
        return watcherCount[_matchId];
    }

    function getPotentialReturn(
        uint256 _matchId,
        address _chosenPlayer,
        uint256 _amount
    ) external view returns (uint256) {
        MatchPool storage pool = matchPools[_matchId];
        uint256 feePercent = ICipherConfig(configContract).getSpectatorFeePercent();

        uint256 opposingPool = (_chosenPlayer == pool.playerA)
            ? pool.poolForPlayerB
            : pool.poolForPlayerA;

        uint256 fee = (opposingPool * feePercent) / 100;
        uint256 distributable = opposingPool - fee;

        uint256 chosenPool = (_chosenPlayer == pool.playerA)
            ? pool.poolForPlayerA
            : pool.poolForPlayerB;

        uint256 newWinningPool = chosenPool + _amount;
        if (newWinningPool == 0) return _amount;

        uint256 share = (_amount * distributable) / newWinningPool;
        return _amount + share;
    }

    receive() external payable {}
}