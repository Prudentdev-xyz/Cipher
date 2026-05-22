// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CipherRanking
/// @notice Manages all player rankings onchain for the CIPHER game
contract CipherRanking {
    // ================================================================
    // ENUMS
    // ================================================================

    enum Tier {
        NOVICE,
        SOLVER,
        DECODER,
        CRYPTIC,
        CIPHER_ELITE
    }

    // ================================================================
    // STRUCTS
    // ================================================================

    struct RankData {
        uint256 totalPoints;
        Tier tier;
        uint256 wins;
        uint256 losses;
        uint256 totalMatches;
        uint256 tokensEarned;
        bool initialized;
    }

    // ================================================================
    // CONSTANTS
    // ================================================================

    uint256 public constant SOLVER_THRESHOLD = 1000;
    uint256 public constant DECODER_THRESHOLD = 3000;
    uint256 public constant CRYPTIC_THRESHOLD = 6000;
    uint256 public constant CIPHER_ELITE_THRESHOLD = 10000;

    uint256 public constant BASE_WIN_POINTS = 100;
    uint256 public constant BASE_LOSS_POINTS = 80;
    uint256 public constant TOKEN_MATCH_BONUS_PCT = 20;
    uint256 public constant STAKE_MODE_TOKEN = 1;

    // ================================================================
    // STATE VARIABLES
    // ================================================================

    address public owner;
    address public configContract;

    mapping(address => RankData) public playerRankings;
    mapping(address => bool) public authorizedCallers;
    address[] public rankedPlayers;

    // ================================================================
    // EVENTS
    // ================================================================

    event PlayerInitialized(address indexed player);
    event RankingUpdated(
        address indexed winner,
        address indexed loser,
        uint256 winPoints,
        uint256 lossPoints
    );
    event TierChanged(address indexed player, Tier oldTier, Tier newTier);
    event CallerAuthorized(address indexed caller);
    event CallerRemoved(address indexed caller);
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    // ================================================================
    // ERRORS
    // ================================================================

    error NotOwner();
    error NotAuthorizedCaller();
    error PlayerAlreadyInitialized(address player);
    error InvalidAddress();
    error LeaderboardLimitTooHigh(uint256 provided, uint256 max);

    // ================================================================
    // MODIFIERS
    // ================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner)
            revert NotAuthorizedCaller();
        _;
    }

    // ================================================================
    // CONSTRUCTOR
    // ================================================================

    constructor(address _configContract) {
        if (_configContract == address(0)) revert InvalidAddress();
        owner = msg.sender;
        configContract = _configContract;
        authorizedCallers[msg.sender] = true;
    }

    // ================================================================
    // ADMIN FUNCTIONS
    // ================================================================

    function addAuthorizedCaller(address _caller) external onlyOwner {
        if (_caller == address(0)) revert InvalidAddress();
        authorizedCallers[_caller] = true;
        emit CallerAuthorized(_caller);
    }

    function removeAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCallers[_caller] = false;
        emit CallerRemoved(_caller);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    // ================================================================
    // CORE FUNCTIONS
    // ================================================================

    /// @notice Initialize a new player on first match
    function initializePlayer(address _player) public onlyAuthorized {
        if (playerRankings[_player].initialized)
            revert PlayerAlreadyInitialized(_player);

        playerRankings[_player] = RankData({
            totalPoints: 0,
            tier: Tier.NOVICE,
            wins: 0,
            losses: 0,
            totalMatches: 0,
            tokensEarned: 0,
            initialized: true
        });

        rankedPlayers.push(_player);
        emit PlayerInitialized(_player);
    }

    /// @notice Update rankings after a match concludes
    /// @param _winner Winner wallet address
    /// @param _loser Loser wallet address
    /// @param _stakeMode 0 = FREE, 1 = TOKEN
    /// @param _tokensWon Tokens won by winner (0 for free match)
    function updateRanking(
        address _winner,
        address _loser,
        uint256 _stakeMode,
        uint256 _tokensWon
    ) external onlyAuthorized {
        // Initialize players if not already done
        if (!playerRankings[_winner].initialized) initializePlayer(_winner);
        if (!playerRankings[_loser].initialized) initializePlayer(_loser);

        (uint256 winPoints, uint256 lossPoints) = calculatePointsChange(
            _winner,
            _loser,
            _stakeMode
        );

        // Update winner
        playerRankings[_winner].totalPoints += winPoints;
        playerRankings[_winner].wins += 1;
        playerRankings[_winner].totalMatches += 1;
        playerRankings[_winner].tokensEarned += _tokensWon;

        // Update loser — floor at 0
        if (playerRankings[_loser].totalPoints >= lossPoints) {
            playerRankings[_loser].totalPoints -= lossPoints;
        } else {
            playerRankings[_loser].totalPoints = 0;
        }
        playerRankings[_loser].losses += 1;
        playerRankings[_loser].totalMatches += 1;

        // Update tiers
        _updateTier(_winner);
        _updateTier(_loser);

        emit RankingUpdated(_winner, _loser, winPoints, lossPoints);
    }

    // ================================================================
    // INTERNAL FUNCTIONS
    // ================================================================

    /// @notice Calculate points change based on tier difference
    function calculatePointsChange(
        address _winner,
        address _loser,
        uint256 _stakeMode
    ) public view returns (uint256 winPoints, uint256 lossPoints) {
        uint256 winnerTier = uint256(playerRankings[_winner].tier);
        uint256 loserTier = uint256(playerRankings[_loser].tier);

        winPoints = BASE_WIN_POINTS;
        lossPoints = BASE_LOSS_POINTS;

        if (winnerTier < loserTier) {
            // Upset — winner was lower tier
            uint256 diff = loserTier - winnerTier;
            winPoints += diff * 40;
            lossPoints += diff * 30;
        } else if (winnerTier > loserTier) {
            // Expected win — winner was higher tier
            uint256 diff = winnerTier - loserTier;
            uint256 winDeduct = diff * 25;
            uint256 lossDeduct = diff * 20;
            winPoints = winPoints > winDeduct ? winPoints - winDeduct : 10;
            lossPoints = lossPoints > lossDeduct ? lossPoints - lossDeduct : 10;
        }

        // Token match bonus +20%
        if (_stakeMode == STAKE_MODE_TOKEN) {
            winPoints = winPoints + ((winPoints * TOKEN_MATCH_BONUS_PCT) / 100);
            lossPoints =
                lossPoints +
                ((lossPoints * TOKEN_MATCH_BONUS_PCT) / 100);
        }
    }

    /// @notice Auto update tier based on current points
    function _updateTier(address _player) internal {
        Tier oldTier = playerRankings[_player].tier;
        uint256 points = playerRankings[_player].totalPoints;
        Tier newTier;

        if (points >= CIPHER_ELITE_THRESHOLD) {
            newTier = Tier.CIPHER_ELITE;
        } else if (points >= CRYPTIC_THRESHOLD) {
            newTier = Tier.CRYPTIC;
        } else if (points >= DECODER_THRESHOLD) {
            newTier = Tier.DECODER;
        } else if (points >= SOLVER_THRESHOLD) {
            newTier = Tier.SOLVER;
        } else {
            newTier = Tier.NOVICE;
        }

        if (newTier != oldTier) {
            playerRankings[_player].tier = newTier;
            emit TierChanged(_player, oldTier, newTier);
        }
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getPlayerRank(
        address _player
    ) external view returns (RankData memory) {
        return playerRankings[_player];
    }

    function getPlayerTier(address _player) external view returns (Tier) {
        return playerRankings[_player].tier;
    }

    function getPlayerPoints(address _player) external view returns (uint256) {
        return playerRankings[_player].totalPoints;
    }

    function getTierThreshold(Tier _tier) external pure returns (uint256) {
        if (_tier == Tier.SOLVER) return SOLVER_THRESHOLD;
        if (_tier == Tier.DECODER) return DECODER_THRESHOLD;
        if (_tier == Tier.CRYPTIC) return CRYPTIC_THRESHOLD;
        if (_tier == Tier.CIPHER_ELITE) return CIPHER_ELITE_THRESHOLD;
        return 0;
    }

    function isInitialized(address _player) external view returns (bool) {
        return playerRankings[_player].initialized;
    }

    function getTotalPlayers() external view returns (uint256) {
        return rankedPlayers.length;
    }

    /// @notice Returns top N players sorted by points
    function getLeaderboard(
        uint256 _limit
    ) external view returns (address[] memory, RankData[] memory) {
        if (_limit > 100) revert LeaderboardLimitTooHigh(_limit, 100);

        uint256 total = rankedPlayers.length;
        uint256 size = _limit < total ? _limit : total;

        // Copy to memory for sorting
        address[] memory addrs = new address[](total);
        uint256[] memory points = new uint256[](total);

        for (uint256 i = 0; i < total; i++) {
            addrs[i] = rankedPlayers[i];
            points[i] = playerRankings[rankedPlayers[i]].totalPoints;
        }

        // Bubble sort descending (small N in practice)
        for (uint256 i = 0; i < total; i++) {
            for (uint256 j = i + 1; j < total; j++) {
                if (points[j] > points[i]) {
                    (points[i], points[j]) = (points[j], points[i]);
                    (addrs[i], addrs[j]) = (addrs[j], addrs[i]);
                }
            }
        }

        address[] memory topAddrs = new address[](size);
        RankData[] memory topData = new RankData[](size);

        for (uint256 i = 0; i < size; i++) {
            topAddrs[i] = addrs[i];
            topData[i] = playerRankings[addrs[i]];
        }

        return (topAddrs, topData);
    }
}
