// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CipherMatchFactory
/// @notice Handles session code pairing and deploys CipherMatch contracts
contract CipherMatchFactory {
    // ================================================================
    // STRUCTS
    // ================================================================

    struct MatchRecord {
        address matchAddress;
        address playerA;
        address playerB;
        uint256 createdAt;
        bool isActive;
    }

    struct PendingPlayer {
        address playerAddress;
        uint256 joinedAt;
    }

    // ================================================================
    // CONSTANTS
    // ================================================================

    uint256 public constant PENDING_TIMEOUT = 300; // 5 minutes

    // ================================================================
    // STATE VARIABLES
    // ================================================================

    address public owner;
    address public configContract;
    address public rankingContract;
    address public spectatorContract;

    uint256 public matchCount;

    // hashed session code => pending player
    mapping(bytes32 => PendingPlayer) public pendingPlayers;

    // hashed session code => active match record
    mapping(bytes32 => MatchRecord) public activeMatches;

    // matchId => match record
    mapping(uint256 => MatchRecord) public allMatches;

    // player => matchIds they participated in
    mapping(address => uint256[]) public playerMatches;

    // player => currently in pending slot
    mapping(address => bool) public playerInPending;

    // ================================================================
    // EVENTS
    // ================================================================

    event MatchPending(bytes32 indexed codeHash, address indexed player);
    event MatchCreated(
        bytes32 indexed codeHash,
        address indexed matchAddress,
        address indexed playerA,
        address playerB
    );
    event MatchCancelled(bytes32 indexed codeHash, address indexed player);
    event PendingExpired(bytes32 indexed codeHash);
    event MatchInactive(uint256 indexed matchId);
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    // ================================================================
    // ERRORS
    // ================================================================

    error NotOwner();
    error AlreadyInPending();
    error NoPendingPlayerFound();
    error PendingSlotExpired();
    error CannotMatchYourself();
    error NotMatchContract();
    error InvalidAddress();
    error MatchNotFound();

    // ================================================================
    // MODIFIERS
    // ================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ================================================================
    // CONSTRUCTOR
    // ================================================================

    constructor(
        address _configContract,
        address _rankingContract,
        address _spectatorContract
    ) {
        if (_configContract == address(0)) revert InvalidAddress();
        if (_rankingContract == address(0)) revert InvalidAddress();

        owner = msg.sender;
        configContract = _configContract;
        rankingContract = _rankingContract;
        spectatorContract = _spectatorContract;
    }

    // ================================================================
    // CORE FUNCTIONS
    // ================================================================

    /// @notice Player enters a session code to find an opponent
    function joinMatch(string memory _sessionCode) external {
        bytes32 codeHash = keccak256(abi.encodePacked(_sessionCode));

        // Check player not already in pending
        if (playerInPending[msg.sender]) revert AlreadyInPending();

        PendingPlayer memory pending = pendingPlayers[codeHash];

        if (pending.playerAddress == address(0)) {
            // No one waiting — store as pending
            pendingPlayers[codeHash] = PendingPlayer({
                playerAddress: msg.sender,
                joinedAt: block.timestamp
            });
            playerInPending[msg.sender] = true;
            emit MatchPending(codeHash, msg.sender);
        } else {
            // Someone is waiting — check validity
            if (pending.playerAddress == msg.sender)
                revert CannotMatchYourself();

            // Check not expired
            if (block.timestamp > pending.joinedAt + PENDING_TIMEOUT) {
                // Clean up expired slot
                playerInPending[pending.playerAddress] = false;
                delete pendingPlayers[codeHash];
                emit PendingExpired(codeHash);

                // Store current player as new pending
                pendingPlayers[codeHash] = PendingPlayer({
                    playerAddress: msg.sender,
                    joinedAt: block.timestamp
                });
                playerInPending[msg.sender] = true;
                emit MatchPending(codeHash, msg.sender);
                return;
            }

            // Valid match — deploy
            address playerA = pending.playerAddress;
            address playerB = msg.sender;

            playerInPending[playerA] = false;
            delete pendingPlayers[codeHash];

            _deployMatch(playerA, playerB, codeHash);
        }
    }

    /// @notice Deploy a new CipherMatch contract for two players
    function _deployMatch(
        address _playerA,
        address _playerB,
        bytes32 _codeHash
    ) internal {
        matchCount += 1;
        uint256 matchId = matchCount;

        // For now store factory address as placeholder
        // Will be replaced with actual CipherMatch deploy in Milestone 1.4
        address matchAddress = address(this);

        MatchRecord memory record = MatchRecord({
            matchAddress: matchAddress,
            playerA: _playerA,
            playerB: _playerB,
            createdAt: block.timestamp,
            isActive: true
        });

        allMatches[matchId] = record;
        activeMatches[_codeHash] = record;

        playerMatches[_playerA].push(matchId);
        playerMatches[_playerB].push(matchId);

        emit MatchCreated(_codeHash, matchAddress, _playerA, _playerB);
    }

    /// @notice Cancel a pending slot
    function cancelPending(string memory _sessionCode) external {
        bytes32 codeHash = keccak256(abi.encodePacked(_sessionCode));
        PendingPlayer memory pending = pendingPlayers[codeHash];

        if (pending.playerAddress == address(0)) revert NoPendingPlayerFound();
        if (pending.playerAddress != msg.sender) revert NoPendingPlayerFound();

        playerInPending[msg.sender] = false;
        delete pendingPlayers[codeHash];

        emit MatchCancelled(codeHash, msg.sender);
    }

    /// @notice Clean up expired pending slot (callable by anyone)
    function cleanExpiredPending(string memory _sessionCode) external {
        bytes32 codeHash = keccak256(abi.encodePacked(_sessionCode));
        PendingPlayer memory pending = pendingPlayers[codeHash];

        if (pending.playerAddress == address(0)) revert NoPendingPlayerFound();
        if (block.timestamp <= pending.joinedAt + PENDING_TIMEOUT)
            revert PendingSlotExpired();

        playerInPending[pending.playerAddress] = false;
        delete pendingPlayers[codeHash];

        emit PendingExpired(codeHash);
    }

    /// @notice Mark a match as inactive — called by CipherMatch on conclusion
    function markMatchInactive(uint256 _matchId) external {
        MatchRecord storage record = allMatches[_matchId];
        if (record.matchAddress == address(0)) revert MatchNotFound();
        if (record.matchAddress != msg.sender) revert NotMatchContract();
        record.isActive = false;
        emit MatchInactive(_matchId);
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getMatch(
        uint256 _matchId
    ) external view returns (MatchRecord memory) {
        return allMatches[_matchId];
    }

    function getActiveMatchByCode(
        string memory _sessionCode
    ) external view returns (MatchRecord memory) {
        bytes32 codeHash = keccak256(abi.encodePacked(_sessionCode));
        return activeMatches[codeHash];
    }

    function getPlayerMatches(
        address _player
    ) external view returns (uint256[] memory) {
        return playerMatches[_player];
    }

    function getPendingPlayer(
        string memory _sessionCode
    ) external view returns (address, uint256) {
        bytes32 codeHash = keccak256(abi.encodePacked(_sessionCode));
        PendingPlayer memory p = pendingPlayers[codeHash];
        return (p.playerAddress, p.joinedAt);
    }

    function getTotalMatchCount() external view returns (uint256) {
        return matchCount;
    }

    function isPlayerInPending(address _player) external view returns (bool) {
        return playerInPending[_player];
    }

    function isMatchActive(uint256 _matchId) external view returns (bool) {
        return allMatches[_matchId].isActive;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}
