// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title CipherConfig
/// @notice Stores all protocol-level parameters for the CIPHER game
contract CipherConfig {
    address public owner;
    address public pendingOwner;

    uint256 public platformFeePercent;
    uint256 public spectatorFeePercent;
    uint256 public roundCount;
    uint256 public roundDurationSeconds;
    uint256 public stakeTimeoutSeconds;
    uint256 public minStakeAmount;
    uint256 public maxStakeAmount;
    address public treasuryAddress;

    string[] public categoryList;

    uint256 public constant STAKE_TIER_1 = 0.01 ether;
    uint256 public constant STAKE_TIER_2 = 0.02 ether;
    uint256 public constant STAKE_TIER_3 = 0.03 ether;
    uint256 public constant STAKE_TIER_4 = 0.04 ether;
    uint256 public constant STAKE_TIER_5 = 0.05 ether;
    uint256 public constant MAX_FEE_PERCENT = 20;

    event FeeUpdated(string feeType, uint256 newFee);
    event ConfigUpdated(string param, uint256 newValue);
    event TreasuryUpdated(address newTreasury);
    event CategoryAdded(string category);
    event CategoryRemoved(uint256 index);
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );
    event OwnershipTransferStarted(address indexed pendingOwner);

    error NotOwner();
    error NotPendingOwner();
    error InvalidFeePercent(uint256 provided, uint256 max);
    error InvalidRoundCount(uint256 provided);
    error InvalidDuration(uint256 provided);
    error InvalidTimeout(uint256 provided);
    error InvalidAddress();
    error CategoryListTooSmall();
    error InvalidStakeRange();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _treasuryAddress) {
        if (_treasuryAddress == address(0)) revert InvalidAddress();
        owner = msg.sender;
        treasuryAddress = _treasuryAddress;
        platformFeePercent = 5;
        spectatorFeePercent = 5;
        roundCount = 6;
        roundDurationSeconds = 30;
        stakeTimeoutSeconds = 120;
        minStakeAmount = STAKE_TIER_1;
        maxStakeAmount = STAKE_TIER_5;

        categoryList.push("Science");
        categoryList.push("Nature");
        categoryList.push("Technology");
        categoryList.push("Objects");
        categoryList.push("Pop Culture");
        categoryList.push("History");
        categoryList.push("Geography");
        categoryList.push("Sports");
        categoryList.push("Food & Drink");
        categoryList.push("Entertainment");
        categoryList.push("Animals");
        categoryList.push("Movies & TV");
        categoryList.push("Music");
        categoryList.push("Fashion");
        categoryList.push("Space");
        categoryList.push("Human Body");
        categoryList.push("Mythology");
        categoryList.push("Cars & Vehicles");
        categoryList.push("Web3 & Crypto");
        categoryList.push("Artificial Intelligence");
    }

    function setPlatformFeePercent(uint256 _fee) external onlyOwner {
        if (_fee > MAX_FEE_PERCENT)
            revert InvalidFeePercent(_fee, MAX_FEE_PERCENT);
        platformFeePercent = _fee;
        emit FeeUpdated("platformFee", _fee);
    }

    function setSpectatorFeePercent(uint256 _fee) external onlyOwner {
        if (_fee > MAX_FEE_PERCENT)
            revert InvalidFeePercent(_fee, MAX_FEE_PERCENT);
        spectatorFeePercent = _fee;
        emit FeeUpdated("spectatorFee", _fee);
    }

    function setRoundCount(uint256 _count) external onlyOwner {
        if (_count < 2 || _count > 20) revert InvalidRoundCount(_count);
        roundCount = _count;
        emit ConfigUpdated("roundCount", _count);
    }

    function setRoundDurationSeconds(uint256 _duration) external onlyOwner {
        if (_duration < 15 || _duration > 120)
            revert InvalidDuration(_duration);
        roundDurationSeconds = _duration;
        emit ConfigUpdated("roundDurationSeconds", _duration);
    }

    function setStakeTimeoutSeconds(uint256 _timeout) external onlyOwner {
        if (_timeout < 60) revert InvalidTimeout(_timeout);
        stakeTimeoutSeconds = _timeout;
        emit ConfigUpdated("stakeTimeoutSeconds", _timeout);
    }

    function setMinStakeAmount(uint256 _amount) external onlyOwner {
        if (_amount >= maxStakeAmount) revert InvalidStakeRange();
        minStakeAmount = _amount;
        emit ConfigUpdated("minStakeAmount", _amount);
    }

    function setMaxStakeAmount(uint256 _amount) external onlyOwner {
        if (_amount <= minStakeAmount) revert InvalidStakeRange();
        maxStakeAmount = _amount;
        emit ConfigUpdated("maxStakeAmount", _amount);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        treasuryAddress = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function addCategory(string memory _category) external onlyOwner {
        categoryList.push(_category);
        emit CategoryAdded(_category);
    }

    function removeCategory(uint256 _index) external onlyOwner {
        if (categoryList.length <= 1) revert CategoryListTooSmall();
        categoryList[_index] = categoryList[categoryList.length - 1];
        categoryList.pop();
        emit CategoryRemoved(_index);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();
        pendingOwner = _newOwner;
        emit OwnershipTransferStarted(_newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function getPlatformFeePercent() external view returns (uint256) {
        return platformFeePercent;
    }
    function getSpectatorFeePercent() external view returns (uint256) {
        return spectatorFeePercent;
    }
    function getRoundCount() external view returns (uint256) {
        return roundCount;
    }
    function getRoundDurationSeconds() external view returns (uint256) {
        return roundDurationSeconds;
    }
    function getStakeTimeoutSeconds() external view returns (uint256) {
        return stakeTimeoutSeconds;
    }
    function getMinStakeAmount() external view returns (uint256) {
        return minStakeAmount;
    }
    function getMaxStakeAmount() external view returns (uint256) {
        return maxStakeAmount;
    }
    function getTreasuryAddress() external view returns (address) {
        return treasuryAddress;
    }
    function getCategoryList() external view returns (string[] memory) {
        return categoryList;
    }
    function getCategoryAt(
        uint256 _index
    ) external view returns (string memory) {
        return categoryList[_index];
    }
    function getCategoryCount() external view returns (uint256) {
        return categoryList.length;
    }

    function isValidStakeAmount(uint256 _amount) external pure returns (bool) {
        return (_amount == STAKE_TIER_1 ||
            _amount == STAKE_TIER_2 ||
            _amount == STAKE_TIER_3 ||
            _amount == STAKE_TIER_4 ||
            _amount == STAKE_TIER_5);
    }

    function isCategoryValid(
        string memory _category
    ) external view returns (bool) {
        for (uint256 i = 0; i < categoryList.length; i++) {
            if (
                keccak256(bytes(categoryList[i])) == keccak256(bytes(_category))
            ) {
                return true;
            }
        }
        return false;
    }
}
