// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICipherConfig {
    function getPlatformFeePercent() external view returns (uint256);
    function getTreasuryAddress() external view returns (address);
    function getRoundCount() external view returns (uint256);
    function getRoundDurationSeconds() external view returns (uint256);
    function getStakeTimeoutSeconds() external view returns (uint256);
    function isValidStakeAmount(uint256 _amount) external pure returns (bool);
    function isCategoryValid(
        string memory _category
    ) external view returns (bool);
}

interface ICipherRanking {
    function updateRanking(
        address _winner,
        address _loser,
        uint256 _stakeMode,
        uint256 _tokensWon
    ) external;
}

interface ICipherSpectator {
    function initializePool(
        uint256 _matchId,
        address _playerA,
        address _playerB
    ) external;
    function closePredictions(uint256 _matchId) external;
    function resolveMatch(uint256 _matchId, address _winner) external;
}

interface ICipherMatchFactory {
    function markMatchInactive(uint256 _matchId) external;
}

/// @title CipherMatch
/// @notice Core game contract — one instance per match
contract CipherMatch {
    // ================================================================
    // ENUMS
    // ================================================================

    enum StakeMode {
        FREE,
        TOKEN
    }

    enum MatchState {
        PENDING_STAKE,
        ACTIVE,
        CONCLUDED,
        CANCELLED
    }

    enum RoundState {
        PENDING_CATEGORY,
        PENDING_GUESS,
        CLOSED
    }

    // ================================================================
    // STRUCTS
    // ================================================================

    struct RoundData {
        uint256 roundNumber;
        address presenter;
        address guesser;
        string category;
        string riddle;
        string sketchDescription;
        string secretWord; // hidden until round closes
        string guess;
        bool isCorrect;
        RoundState state;
        uint256 startedAt;
    }

    // ================================================================
    // STATE VARIABLES
    // ================================================================

    uint256 public matchId;
    address public playerA;
    address public playerB;

    StakeMode public stakeMode;
    uint256 public stakeAmount;
    bool public playerAStakeConfirmed;
    bool public playerBStakeConfirmed;
    uint256 public stakeDeadline;

    MatchState public matchState;

    RoundData[] public rounds;
    uint256 public currentRound;
    uint256 public scoreA;
    uint256 public scoreB;
    address public winner;
    bool public isTiebreaker;

    address public configContract;
    address public rankingContract;
    address public spectatorContract;
    address public factoryContract;
    address public scheduler;

    // ================================================================
    // EVENTS
    // ================================================================

    event MatchInitialized(
        uint256 indexed matchId,
        address playerA,
        address playerB
    );
    event StakeConfirmed(address indexed player, uint256 amount);
    event MatchStarted(
        uint256 indexed matchId,
        address playerA,
        address playerB
    );
    event CategorySelected(
        uint256 indexed matchId,
        uint256 round,
        string category
    );
    event ChallengeGenerated(
        uint256 indexed matchId,
        uint256 round,
        string riddle,
        string sketchDescription
    );
    event GuessSubmitted(
        uint256 indexed matchId,
        uint256 round,
        address guesser
    );
    event RoundClosed(
        uint256 indexed matchId,
        uint256 round,
        string secretWord,
        string guess,
        bool correct
    );
    event MatchConcluded(
        uint256 indexed matchId,
        address winner,
        uint256 scoreA,
        uint256 scoreB
    );
    event PayoutDistributed(
        uint256 indexed matchId,
        address winner,
        uint256 payout,
        uint256 fee
    );
    event MatchCancelled(uint256 indexed matchId, string reason);
    event TiebreakerStarted(uint256 indexed matchId, uint256 round);

    // ================================================================
    // ERRORS
    // ================================================================

    error NotAPlayer();
    error NotPresenter();
    error NotGuesser();
    error NotScheduler();
    error MatchNotActive();
    error MatchNotPending();
    error StakeAlreadyConfirmed();
    error StakeModeMismatch();
    error StakeAmountMismatch();
    error StakeTimeoutReached();
    error InvalidStakeAmount();
    error InvalidCategory();
    error RoundNotOpen();
    error RoundAlreadyClosed();
    error InvalidAddress();

    // ================================================================
    // MODIFIERS
    // ================================================================

    modifier onlyPlayers() {
        if (msg.sender != playerA && msg.sender != playerB) revert NotAPlayer();
        _;
    }

    modifier onlyActive() {
        if (matchState != MatchState.ACTIVE) revert MatchNotActive();
        _;
    }

    modifier onlySchedulerOrPlayers() {
        if (
            msg.sender != scheduler &&
            msg.sender != playerA &&
            msg.sender != playerB
        ) revert NotScheduler();
        _;
    }

    // ================================================================
    // CONSTRUCTOR
    // ================================================================

    constructor(
        uint256 _matchId,
        address _playerA,
        address _playerB,
        address _configContract,
        address _rankingContract,
        address _spectatorContract,
        address _factoryContract,
        address _scheduler
    ) {
        matchId = _matchId;
        playerA = _playerA;
        playerB = _playerB;
        configContract = _configContract;
        rankingContract = _rankingContract;
        spectatorContract = _spectatorContract;
        factoryContract = _factoryContract;
        scheduler = _scheduler;
        matchState = MatchState.PENDING_STAKE;
        stakeDeadline =
            block.timestamp +
            ICipherConfig(_configContract).getStakeTimeoutSeconds();

        emit MatchInitialized(_matchId, _playerA, _playerB);
    }

    // ================================================================
    // STAKE FUNCTIONS
    // ================================================================

    /// @notice Both players call this to confirm stake and start match
    function confirmStake(
        uint256 _mode,
        uint256 _amount
    ) external payable onlyPlayers {
        if (matchState != MatchState.PENDING_STAKE) revert MatchNotPending();
        if (block.timestamp > stakeDeadline) revert StakeTimeoutReached();

        bool isPlayerA = msg.sender == playerA;

        if (isPlayerA && playerAStakeConfirmed) revert StakeAlreadyConfirmed();
        if (!isPlayerA && playerBStakeConfirmed) revert StakeAlreadyConfirmed();

        StakeMode mode = StakeMode(_mode);

        if (mode == StakeMode.TOKEN) {
            if (!ICipherConfig(configContract).isValidStakeAmount(_amount))
                revert InvalidStakeAmount();
            if (msg.value != _amount) revert InvalidStakeAmount();
        }

        // First confirmation — set mode and amount
        if (!playerAStakeConfirmed && !playerBStakeConfirmed) {
            stakeMode = mode;
            stakeAmount = _amount;
        } else {
            // Second confirmation — must match first
            if (mode != stakeMode) revert StakeModeMismatch();
            if (_amount != stakeAmount) revert StakeAmountMismatch();
        }

        if (isPlayerA) {
            playerAStakeConfirmed = true;
        } else {
            playerBStakeConfirmed = true;
        }

        emit StakeConfirmed(msg.sender, _amount);

        // Both confirmed — start match
        if (playerAStakeConfirmed && playerBStakeConfirmed) {
            _startMatch();
        }
    }

    /// @notice Cancel match and refund stakes
    function cancelMatch() external onlyPlayers {
        if (
            matchState == MatchState.CONCLUDED ||
            matchState == MatchState.CANCELLED
        ) revert MatchNotPending();

        matchState = MatchState.CANCELLED;

        // Refund stakes
        if (stakeMode == StakeMode.TOKEN) {
            if (playerAStakeConfirmed && stakeAmount > 0) {
                payable(playerA).transfer(stakeAmount);
            }
            if (playerBStakeConfirmed && stakeAmount > 0) {
                payable(playerB).transfer(stakeAmount);
            }
        }

        emit MatchCancelled(matchId, "cancelled by player");
    }

    // ================================================================
    // INTERNAL — MATCH START
    // ================================================================

    function _startMatch() internal {
        matchState = MatchState.ACTIVE;
        currentRound = 1;

        // PlayerA presents first
        _initRound(currentRound, playerA, playerB);

        // Initialize spectator pool
        if (spectatorContract != address(0)) {
            ICipherSpectator(spectatorContract).initializePool(
                matchId,
                playerA,
                playerB
            );
        }

        emit MatchStarted(matchId, playerA, playerB);
    }

    function _initRound(
        uint256 _roundNum,
        address _presenter,
        address _guesser
    ) internal {
        rounds.push(
            RoundData({
                roundNumber: _roundNum,
                presenter: _presenter,
                guesser: _guesser,
                category: "",
                riddle: "",
                sketchDescription: "",
                secretWord: "",
                guess: "",
                isCorrect: false,
                state: RoundState.PENDING_CATEGORY,
                startedAt: 0
            })
        );
    }

    // ================================================================
    // ROUND FUNCTIONS
    // ================================================================

    /// @notice Presenter picks a category to start the round
    function selectCategory(string memory _category) external onlyActive {
        RoundData storage round = rounds[currentRound - 1];
        if (msg.sender != round.presenter) revert NotPresenter();
        if (round.state != RoundState.PENDING_CATEGORY) revert RoundNotOpen();
        if (!ICipherConfig(configContract).isCategoryValid(_category))
            revert InvalidCategory();

        round.category = _category;
        round.startedAt = block.timestamp;

        emit CategorySelected(matchId, currentRound, _category);

        // Close spectator predictions on final round
        uint256 totalRounds = ICipherConfig(configContract).getRoundCount();
        if (currentRound == totalRounds && spectatorContract != address(0)) {
            ICipherSpectator(spectatorContract).closePredictions(matchId);
        }

        _generateChallenge(_category);
    }

    /// @notice Internal — generates challenge via Ritual AI (mocked for testnet)
    function _generateChallenge(string memory _category) internal {
        RoundData storage round = rounds[currentRound - 1];

        // ----------------------------------------------------------------
        // RITUAL AI PRECOMPILE CALL (MOCK FOR NOW)
        // On Ritual Mainnet this will be:
        //   ritualAI.call({
        //     model: "ritual-llm-v1",
        //     prompt: "Generate secret_word, riddle, sketch_description
        //              for category: " + _category,
        //     confidential: true,
        //     max_tokens: 200
        //   })
        // secret_word → TEE encrypted, stored as encryptedSecretWord
        // riddle + sketchDescription → public state
        // ----------------------------------------------------------------

        round.secretWord = _mockGenerateSecret(_category);
        round.riddle = string(
            abi.encodePacked("This is a riddle about something in: ", _category)
        );
        round.sketchDescription = string(
            abi.encodePacked("A simple sketch representing: ", _category)
        );
        round.state = RoundState.PENDING_GUESS;

        emit ChallengeGenerated(
            matchId,
            currentRound,
            round.riddle,
            round.sketchDescription
        );
    }

    /// @notice Mock secret word generator — replaced by Ritual AI on mainnet
    function _mockGenerateSecret(
        string memory _category
    ) internal pure returns (string memory) {
        bytes32 hash = keccak256(abi.encodePacked(_category));
        bytes1 first = hash[0];
        if (uint8(first) % 5 == 0) return "TELESCOPE";
        if (uint8(first) % 5 == 1) return "SATELLITE";
        if (uint8(first) % 5 == 2) return "BLOCKCHAIN";
        if (uint8(first) % 5 == 3) return "ALGORITHM";
        return "PROTOCOL";
    }

    /// @notice Guesser submits their answer
    function submitGuess(string memory _guess) external onlyActive {
        RoundData storage round = rounds[currentRound - 1];
        if (msg.sender != round.guesser) revert NotGuesser();
        if (round.state != RoundState.PENDING_GUESS) revert RoundNotOpen();

        round.guess = _guess;
        emit GuessSubmitted(matchId, currentRound, msg.sender);
    }

    /// @notice Close round — called by Ritual Scheduler or manually after 30s
    function closeRound() external onlySchedulerOrPlayers onlyActive {
        RoundData storage round = rounds[currentRound - 1];
        if (round.state == RoundState.CLOSED) revert RoundAlreadyClosed();
        if (round.state != RoundState.PENDING_GUESS) revert RoundNotOpen();

        round.state = RoundState.CLOSED;

        // Evaluate guess — case insensitive
        bool correct = false;
        if (bytes(round.guess).length > 0) {
            correct = _stringsEqualIgnoreCase(round.guess, round.secretWord);
        }

        round.isCorrect = correct;

        if (correct) {
            if (round.guesser == playerA) {
                scoreA += 1;
            } else {
                scoreB += 1;
            }
        }

        emit RoundClosed(
            matchId,
            currentRound,
            round.secretWord,
            round.guess,
            correct
        );

        uint256 totalRounds = ICipherConfig(configContract).getRoundCount();

        if (currentRound < totalRounds) {
            _startNextRound();
        } else {
            _concludeMatch();
        }
    }

    // ================================================================
    // INTERNAL — ROUND + MATCH MANAGEMENT
    // ================================================================

    function _startNextRound() internal {
        currentRound += 1;

        // Swap roles
        address prevPresenter = rounds[currentRound - 2].presenter;
        address newPresenter = (prevPresenter == playerA) ? playerB : playerA;
        address newGuesser = (newPresenter == playerA) ? playerB : playerA;

        _initRound(currentRound, newPresenter, newGuesser);
    }

    function _concludeMatch() internal {
        if (scoreA > scoreB) {
            winner = playerA;
        } else if (scoreB > scoreA) {
            winner = playerB;
        } else {
            // Tie — start tiebreaker
            isTiebreaker = true;
            currentRound += 1;

            address lastPresenter = rounds[rounds.length - 1].presenter;
            address tbPresenter = (lastPresenter == playerA)
                ? playerB
                : playerA;
            address tbGuesser = (tbPresenter == playerA) ? playerB : playerA;

            _initRound(currentRound, tbPresenter, tbGuesser);
            emit TiebreakerStarted(matchId, currentRound);
            return;
        }

        _finalizeMatch();
    }

    function _finalizeMatch() internal {
        address loser = (winner == playerA) ? playerB : playerA;

        matchState = MatchState.CONCLUDED;

        uint256 payout = 0;
        if (stakeMode == StakeMode.TOKEN) {
            payout = _distributePayout();
        }

        // Update rankings
        ICipherRanking(rankingContract).updateRanking(
            winner,
            loser,
            uint256(stakeMode),
            payout
        );

        // Resolve spectator pool
        if (spectatorContract != address(0)) {
            ICipherSpectator(spectatorContract).resolveMatch(matchId, winner);
        }

        // Mark inactive in factory
        // ICipherMatchFactory(factoryContract).markMatchInactive(matchId);

        emit MatchConcluded(matchId, winner, scoreA, scoreB);
    }

    function _distributePayout() internal returns (uint256 payout) {
        uint256 totalPot = stakeAmount * 2;
        uint256 feePercent = ICipherConfig(configContract)
            .getPlatformFeePercent();
        uint256 fee = (totalPot * feePercent) / 100;
        payout = totalPot - fee;

        address treasury = ICipherConfig(configContract).getTreasuryAddress();

        payable(winner).transfer(payout);
        payable(treasury).transfer(fee);

        emit PayoutDistributed(matchId, winner, payout, fee);
    }

    // ================================================================
    // UTILITY
    // ================================================================

    function _stringsEqualIgnoreCase(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        if (ba.length != bb.length) return false;
        for (uint256 i = 0; i < ba.length; i++) {
            bytes1 ca = ba[i];
            bytes1 cb = bb[i];
            // lowercase if uppercase
            if (ca >= 0x41 && ca <= 0x5A) ca = bytes1(uint8(ca) + 32);
            if (cb >= 0x41 && cb <= 0x5A) cb = bytes1(uint8(cb) + 32);
            if (ca != cb) return false;
        }
        return true;
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getMatchState() external view returns (MatchState) {
        return matchState;
    }
    function getScore() external view returns (uint256, uint256) {
        return (scoreA, scoreB);
    }
    function getCurrentRound() external view returns (uint256) {
        return currentRound;
    }
    function getWinner() external view returns (address) {
        return winner;
    }
    function getPlayers() external view returns (address, address) {
        return (playerA, playerB);
    }
    function getRoundCount() external view returns (uint256) {
        return rounds.length;
    }

    function getRoundData(
        uint256 _roundNumber
    ) external view returns (RoundData memory) {
        return rounds[_roundNumber - 1];
    }

    receive() external payable {}
}
