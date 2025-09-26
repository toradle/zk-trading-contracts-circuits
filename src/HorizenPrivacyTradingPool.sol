// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IZKVerifier.sol";
import "./interfaces/IZEN.sol";
import "./interfaces/ISingularityIntegration.sol";
import "./libraries/ZKTypes.sol";
import "./libraries/HorizenConfig.sol";
import "./libraries/Poseidon.sol";

/**
 * @title HorizenPrivacyTradingPool
 * @dev Enhanced ZK Trading Pool with Horizen L3 privacy stack integration
 * @notice Integrates with Singularity for stealth transactions and uses ZEN as primary token
 */
contract HorizenPrivacyTradingPool is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IZEN;
    using Poseidon for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    uint256 public constant COMMITMENT_PHASE_DURATION = HorizenConfig.MIN_COMMITMENT_TIME;
    uint256 public constant MIN_TRADE_AMOUNT = 1e6;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE = 1000; // 10%

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    // Core tokens
    IERC20 public immutable baseToken;
    IZEN public immutable zenToken;
    IZKVerifier public immutable zkVerifier;
    ISingularityIntegration public immutable singularityIntegration;

    // Trading state
    mapping(bytes32 => ZKTypes.TradeCommitment) public commitments;
    mapping(bytes32 => bool) public nullifierHashes;
    mapping(bytes32 => ZKTypes.PrivateOrder) public privateOrders;
    mapping(address => uint256) public balances;
    mapping(address => uint256) private nonces;

    // Horizen-specific state
    mapping(address => bool) public isHorizenUser;
    mapping(address => bytes32) public userPrivacyKeys;
    mapping(bytes32 => uint256) public privacyScores;

    bytes32[] public activeOrderHashes;
    bytes32 public merkleRoot;
    uint256 public tradingFee = 30; // 0.3%
    uint8 public defaultPrivacyLevel = HorizenConfig.DEFAULT_PRIVACY_LEVEL;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event HorizenUserRegistered(address indexed user, bytes32 privacyKey);
    event SingularityTradeExecuted(
        bytes32 indexed stealthId,
        address indexed trader,
        uint256 amount,
        bool isPrivate
    );
    event PrivacyLevelAdjusted(address indexed user, uint8 newLevel);
    event ZENStakingReward(address indexed user, uint256 reward);

    // Legacy events
    event CommitmentMade(bytes32 indexed commitment, address indexed user, uint256 timestamp);
    event TradeExecuted(
        bytes32 indexed commitment,
        address indexed trader,
        uint256 amount,
        uint256 price,
        bool isBuyOrder
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error NotHorizenNetwork();
    error InvalidPrivacyKey();
    error InsufficientZENBalance();
    error SingularityIntegrationFailed();
    error PrivacyLevelTooLow();

    // =============================================================================
    // MODIFIERS
    // =============================================================================

    modifier onlyHorizenNetwork() {
        if (!HorizenConfig.isHorizenSupported()) revert NotHorizenNetwork();
        _;
    }

    modifier onlyRegisteredUser() {
        require(isHorizenUser[msg.sender], "Must be registered Horizen user");
        _;
    }

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    constructor(
        address _baseToken,
        address _zkVerifier,
        address _singularityIntegration,
        address _owner
    ) Ownable(_owner) onlyHorizenNetwork {
        require(_baseToken != address(0), "Invalid base token");
        require(_zkVerifier != address(0), "Invalid verifier");
        require(_singularityIntegration != address(0), "Invalid Singularity integration");

        baseToken = IERC20(_baseToken);
        zenToken = IZEN(HorizenConfig.getZENAddress());
        zkVerifier = IZKVerifier(_zkVerifier);
        singularityIntegration = ISingularityIntegration(_singularityIntegration);
    }

    // =============================================================================
    // HORIZEN INTEGRATION FUNCTIONS
    // =============================================================================

    /**
     * @dev Register as Horizen user with Singularity privacy integration
     * @param privacyKey Unique privacy key for Singularity
     * @param privacyLevel Desired privacy level (0-100)
     */
    function registerHorizenUser(
        bytes32 privacyKey,
        uint8 privacyLevel
    ) external nonReentrant whenNotPaused {
        require(privacyKey != bytes32(0), "Invalid privacy key");
        require(privacyLevel <= 100, "Privacy level too high");
        require(!isHorizenUser[msg.sender], "Already registered");

        // Create privacy profile through Singularity
        bool success = singularityIntegration.createPrivacyProfile(privacyKey, privacyLevel);
        if (!success) revert SingularityIntegrationFailed();

        isHorizenUser[msg.sender] = true;
        userPrivacyKeys[msg.sender] = privacyKey;
        privacyScores[privacyKey] = privacyLevel;

        emit HorizenUserRegistered(msg.sender, privacyKey);
    }

    /**
     * @dev Execute private trade through Singularity stealth transaction
     * @param commitment Trade commitment
     * @param proof ZK proof for the trade
     * @param nullifierHash Nullifier to prevent double-spending
     * @param amount Trade amount
     * @param price Trade price
     * @param isBuyOrder True for buy, false for sell
     * @param useStealthMode Enable Singularity stealth mode
     */
    function executeHorizenPrivateTrade(
        bytes32 commitment,
        ZKTypes.Proof memory proof,
        bytes32 nullifierHash,
        uint256 amount,
        uint256 price,
        bool isBuyOrder,
        bool useStealthMode
    ) external nonReentrant whenNotPaused onlyRegisteredUser {
        ZKTypes.TradeCommitment storage tradeCommitment = commitments[commitment];

        // Validate commitment and proof
        require(tradeCommitment.timestamp != 0, "Commitment not found");
        require(!tradeCommitment.executed, "Already executed");
        require(
            block.timestamp >= tradeCommitment.timestamp + COMMITMENT_PHASE_DURATION,
            "Commitment not ready"
        );
        require(!nullifierHashes[nullifierHash], "Nullifier already used");

        // Verify ZK proof
        bool proofValid = zkVerifier.verifyProof(proof.a, proof.b, proof.c, [uint256(commitment)]);
        require(proofValid, "Invalid proof");

        // Mark nullifier as used
        nullifierHashes[nullifierHash] = true;
        tradeCommitment.executed = true;
        tradeCommitment.nullifierHash = nullifierHash;

        if (useStealthMode) {
            // Execute through Singularity stealth transaction
            bytes32 stealthId = _executeStealthTrade(
                tradeCommitment.trader,
                amount,
                price,
                isBuyOrder
            );
            emit SingularityTradeExecuted(stealthId, tradeCommitment.trader, amount, true);
        } else {
            // Execute regular private trade
            _executeTrade(tradeCommitment.trader, amount, price, isBuyOrder);
            emit TradeExecuted(commitment, tradeCommitment.trader, amount, price, isBuyOrder);
        }

        // Award ZEN staking rewards for privacy usage
        _distributeZENRewards(msg.sender, amount);
    }

    /**
     * @dev Deposit ZEN tokens for enhanced privacy features
     * @param amount Amount of ZEN to deposit
     */
    function depositZEN(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");

        zenToken.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;

        // Boost privacy level based on ZEN stake
        _updatePrivacyLevel(msg.sender);

        emit BalanceDeposited(msg.sender, address(zenToken), amount);
    }

    /**
     * @dev Withdraw ZEN tokens
     * @param amount Amount to withdraw
     */
    function withdrawZEN(uint256 amount) external nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        zenToken.safeTransfer(msg.sender, amount);

        // Update privacy level after withdrawal
        _updatePrivacyLevel(msg.sender);

        emit BalanceWithdrawn(msg.sender, address(zenToken), amount);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @dev Execute stealth trade through Singularity integration
     */
    function _executeStealthTrade(
        address trader,
        uint256 amount,
        uint256 price,
        bool isBuyOrder
    ) internal returns (bytes32 stealthId) {
        require(amount >= MIN_TRADE_AMOUNT, "Invalid amount");

        uint256 quoteAmount = (amount * price) / 1e18;
        uint256 fee = (quoteAmount * tradingFee) / FEE_DENOMINATOR;

        // Prepare stealth transaction data
        bytes memory txData = abi.encode(amount, price, isBuyOrder, fee);

        // Execute through Singularity
        stealthId = singularityIntegration.executeStealthTransaction(
            trader,
            quoteAmount,
            txData
        );

        // Update balances privately
        if (isBuyOrder) {
            require(balances[trader] >= quoteAmount, "Insufficient balance");
            balances[trader] -= quoteAmount;
            baseToken.safeTransfer(trader, amount);
        } else {
            baseToken.safeTransferFrom(trader, address(this), amount);
            balances[trader] += quoteAmount - fee;
        }

        return stealthId;
    }

    /**
     * @dev Update user's privacy level based on ZEN stake
     */
    function _updatePrivacyLevel(address user) internal {
        if (!isHorizenUser[user]) return;

        uint256 zenBalance = balances[user];
        bytes32 privacyKey = userPrivacyKeys[user];

        // Calculate new privacy level based on ZEN stake
        uint8 newLevel = defaultPrivacyLevel;
        if (zenBalance >= 1000e18) newLevel = 95; // High privacy for 1000+ ZEN
        else if (zenBalance >= 100e18) newLevel = 85; // Medium-high for 100+ ZEN
        else if (zenBalance >= 10e18) newLevel = 75; // Medium for 10+ ZEN

        if (privacyScores[privacyKey] != newLevel) {
            privacyScores[privacyKey] = newLevel;
            singularityIntegration.updatePrivacyLevel(newLevel);
            emit PrivacyLevelAdjusted(user, newLevel);
        }
    }

    /**
     * @dev Distribute ZEN rewards for using privacy features
     */
    function _distributeZENRewards(address user, uint256 tradeAmount) internal {
        uint256 rewardRate = privacyScores[userPrivacyKeys[user]]; // Higher privacy = higher rewards
        uint256 reward = (tradeAmount * rewardRate) / (FEE_DENOMINATOR * 10);

        if (reward > 0 && zenToken.balanceOf(address(this)) >= reward) {
            balances[user] += reward;
            emit ZENStakingReward(user, reward);
        }
    }

    /**
     * @dev Legacy trade execution function
     */
    function _executeTrade(address trader, uint256 amount, uint256 price, bool isBuyOrder) internal {
        require(amount >= MIN_TRADE_AMOUNT, "Invalid amount");

        uint256 quoteAmount = (amount * price) / 1e18;
        uint256 fee = (quoteAmount * tradingFee) / FEE_DENOMINATOR;
        uint256 netQuoteAmount = quoteAmount - fee;

        if (isBuyOrder) {
            require(balances[trader] >= quoteAmount, "Insufficient balance");
            balances[trader] -= quoteAmount;
            baseToken.safeTransfer(trader, amount);
        } else {
            baseToken.safeTransferFrom(trader, address(this), amount);
            balances[trader] += netQuoteAmount;
        }

        // Collect fees in ZEN
        if (fee > 0) {
            zenToken.safeTransfer(owner(), fee);
        }
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get user's privacy profile
     */
    function getUserPrivacyProfile(address user)
        external
        view
        returns (
            bool isRegistered,
            bytes32 privacyKey,
            uint8 privacyLevel,
            bool stealthEnabled
        )
    {
        isRegistered = isHorizenUser[user];
        privacyKey = userPrivacyKeys[user];
        privacyLevel = uint8(privacyScores[privacyKey]);
        stealthEnabled = isRegistered ?
            singularityIntegration.isStealthModeEnabled(user) : false;
    }

    /**
     * @dev Get ZEN token address for current network
     */
    function getZENAddress() external view returns (address) {
        return address(zenToken);
    }

    /**
     * @dev Get network information
     */
    function getNetworkInfo()
        external
        view
        returns (
            string memory networkName,
            uint256 chainId,
            bool isSupported
        )
    {
        return (
            HorizenConfig.getNetworkName(),
            block.chainid,
            HorizenConfig.isHorizenSupported()
        );
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /**
     * @dev Set default privacy level for new users
     */
    function setDefaultPrivacyLevel(uint8 newLevel) external onlyOwner {
        require(newLevel <= 100, "Invalid privacy level");
        defaultPrivacyLevel = newLevel;
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // Legacy events for compatibility
    event BalanceDeposited(address indexed user, address indexed token, uint256 amount);
    event BalanceWithdrawn(address indexed user, address indexed token, uint256 amount);
}