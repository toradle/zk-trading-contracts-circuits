// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HorizenPrivacyTradingPool.sol";
import "./ZKOrderbook.sol";
import "./interfaces/IZEN.sol";
import "./libraries/HorizenConfig.sol";

/**
 * @title HorizenTradingFactory
 * @dev Enhanced factory with Horizen L3 integration and ZEN-powered governance
 * @notice Deploys privacy-enhanced trading pools with Singularity integration
 */
contract HorizenTradingFactory is Ownable, ReentrancyGuard {
    using HorizenConfig for *;

    // =============================================================================
    // STRUCTS
    // =============================================================================

    struct HorizenPoolInfo {
        address poolAddress;
        address orderbookAddress;
        address baseToken;
        address zenToken;
        address creator;
        uint256 createdAt;
        bool isActive;
        string name;
        uint8 privacyLevel;
        uint256 zenStaked;
        bool singularityEnabled;
    }

    struct PoolCreationParams {
        address baseToken;
        string poolName;
        uint8 desiredPrivacyLevel;
        bool enableSingularity;
        uint256 zenStakeAmount;
    }

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    // Pool management
    mapping(bytes32 => HorizenPoolInfo) public pools;
    mapping(address => bytes32[]) public userPools;
    mapping(address => bytes32) public tokenPools; // baseToken => poolId (ZEN is always quote)
    bytes32[] public allPools;

    // Horizen integration
    IZEN public immutable zenToken;
    address public immutable zkVerifier;
    address public immutable singularityIntegration;

    // Governance and fees
    uint256 public poolCreationFee = 100e18; // 100 ZEN
    uint256 public protocolFee = 100; // 1%
    address public feeRecipient;
    uint256 public totalZENLocked;

    // Developer program
    mapping(address => bool) public isDeveloperGrantee;
    mapping(address => uint256) public granteeAllocations;
    uint256 public constant DEVELOPER_PROGRAM_TOTAL = 1_000_000e18; // 1M ZEN
    uint256 public developerProgramUsed;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event HorizenPoolCreated(
        bytes32 indexed poolId,
        address indexed creator,
        address poolAddress,
        address orderbookAddress,
        address baseToken,
        uint8 privacyLevel,
        uint256 zenStaked,
        string name
    );

    event ZENStaked(bytes32 indexed poolId, address indexed staker, uint256 amount);
    event SingularityEnabled(bytes32 indexed poolId, address indexed pool);
    event DeveloperGrantApproved(address indexed developer, uint256 allocation);
    event PrivacyLevelUpgraded(bytes32 indexed poolId, uint8 newLevel);

    // =============================================================================
    // ERRORS
    // =============================================================================

    error InsufficientZENBalance();
    error PoolAlreadyExists();
    error InvalidPrivacyLevel();
    error DeveloperProgramExhausted();
    error NotHorizenNetwork();

    // =============================================================================
    // MODIFIERS
    // =============================================================================

    modifier onlyHorizenNetwork() {
        if (!HorizenConfig.isHorizenSupported()) revert NotHorizenNetwork();
        _;
    }

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    constructor(
        address _zkVerifier,
        address _singularityIntegration,
        address _feeRecipient
    ) Ownable(msg.sender) onlyHorizenNetwork {
        require(_zkVerifier != address(0), "Invalid verifier");
        require(_singularityIntegration != address(0), "Invalid Singularity");

        zenToken = IZEN(HorizenConfig.getZENAddress());
        zkVerifier = _zkVerifier;
        singularityIntegration = _singularityIntegration;
        feeRecipient = _feeRecipient != address(0) ? _feeRecipient : msg.sender;
    }

    // =============================================================================
    // MAIN FUNCTIONS
    // =============================================================================

    /**
     * @dev Create enhanced trading pool with Horizen L3 privacy features
     * @param params Pool creation parameters
     * @return poolAddress Address of created trading pool
     * @return orderbookAddress Address of created orderbook
     */
    function createHorizenTradingPool(
        PoolCreationParams calldata params
    ) external nonReentrant returns (address poolAddress, address orderbookAddress) {
        require(params.baseToken != address(zenToken), "Use ZEN as quote token only");
        require(params.desiredPrivacyLevel <= 100, "Invalid privacy level");
        require(params.zenStakeAmount >= poolCreationFee, "Insufficient ZEN stake");

        bytes32 poolId = _getPoolId(params.baseToken);
        if (pools[poolId].poolAddress != address(0)) revert PoolAlreadyExists();

        // Transfer ZEN stake (includes creation fee)
        zenToken.transferFrom(msg.sender, address(this), params.zenStakeAmount);

        // Deploy Horizen privacy-enhanced trading pool
        HorizenPrivacyTradingPool pool = new HorizenPrivacyTradingPool(
            params.baseToken,
            zkVerifier,
            singularityIntegration,
            msg.sender
        );
        poolAddress = address(pool);

        // Deploy orderbook
        ZKOrderbook orderbook = new ZKOrderbook(zkVerifier, poolAddress);
        orderbookAddress = address(orderbook);

        // Store enhanced pool info
        pools[poolId] = HorizenPoolInfo({
            poolAddress: poolAddress,
            orderbookAddress: orderbookAddress,
            baseToken: params.baseToken,
            zenToken: address(zenToken),
            creator: msg.sender,
            createdAt: block.timestamp,
            isActive: true,
            name: params.poolName,
            privacyLevel: params.desiredPrivacyLevel,
            zenStaked: params.zenStakeAmount,
            singularityEnabled: params.enableSingularity
        });

        // Update mappings
        userPools[msg.sender].push(poolId);
        tokenPools[params.baseToken] = poolId;
        allPools.push(poolId);
        totalZENLocked += params.zenStakeAmount;

        // Transfer fee to recipient, rest stays as stake
        zenToken.transfer(feeRecipient, poolCreationFee);

        emit HorizenPoolCreated(
            poolId,
            msg.sender,
            poolAddress,
            orderbookAddress,
            params.baseToken,
            params.desiredPrivacyLevel,
            params.zenStakeAmount,
            params.poolName
        );

        return (poolAddress, orderbookAddress);
    }

    /**
     * @dev Create subsidized pool for developer program participants
     * @param params Pool creation parameters
     * @return poolAddress Address of created trading pool
     * @return orderbookAddress Address of created orderbook
     */
    function createDeveloperPool(
        PoolCreationParams calldata params
    ) external nonReentrant returns (address poolAddress, address orderbookAddress) {
        require(isDeveloperGrantee[msg.sender], "Not approved developer");
        require(granteeAllocations[msg.sender] >= params.zenStakeAmount, "Exceeds allocation");
        require(
            developerProgramUsed + params.zenStakeAmount <= DEVELOPER_PROGRAM_TOTAL,
            "Program exhausted"
        );

        // Use developer allocation instead of user funds
        granteeAllocations[msg.sender] -= params.zenStakeAmount;
        developerProgramUsed += params.zenStakeAmount;

        // Create pool with same logic but subsidized
        return _createPoolInternal(params, true);
    }

    /**
     * @dev Stake additional ZEN to upgrade pool privacy level
     * @param poolId Pool identifier
     * @param additionalStake Additional ZEN to stake
     */
    function stakeZENForPrivacy(
        bytes32 poolId,
        uint256 additionalStake
    ) external nonReentrant {
        HorizenPoolInfo storage pool = pools[poolId];
        require(pool.poolAddress != address(0), "Pool not found");
        require(additionalStake > 0, "Invalid stake amount");

        zenToken.transferFrom(msg.sender, address(this), additionalStake);

        pool.zenStaked += additionalStake;
        totalZENLocked += additionalStake;

        // Calculate new privacy level based on total ZEN staked
        uint8 newPrivacyLevel = _calculatePrivacyLevel(pool.zenStaked);
        if (newPrivacyLevel > pool.privacyLevel) {
            pool.privacyLevel = newPrivacyLevel;
            emit PrivacyLevelUpgraded(poolId, newPrivacyLevel);
        }

        emit ZENStaked(poolId, msg.sender, additionalStake);
    }

    // =============================================================================
    // DEVELOPER PROGRAM FUNCTIONS
    // =============================================================================

    /**
     * @dev Approve developer for grant program
     * @param developer Developer address
     * @param allocation ZEN allocation amount
     */
    function approveDeveloperGrant(
        address developer,
        uint256 allocation
    ) external onlyOwner {
        require(
            developerProgramUsed + allocation <= DEVELOPER_PROGRAM_TOTAL,
            "Exceeds program total"
        );

        isDeveloperGrantee[developer] = true;
        granteeAllocations[developer] = allocation;

        emit DeveloperGrantApproved(developer, allocation);
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get enhanced pool information
     * @param poolId Pool identifier
     * @return pool Complete pool information
     */
    function getHorizenPool(bytes32 poolId)
        external
        view
        returns (HorizenPoolInfo memory pool)
    {
        return pools[poolId];
    }

    /**
     * @dev Get pool by base token (ZEN is always quote)
     * @param baseToken Base token address
     * @return pool Pool information
     */
    function getPoolByToken(address baseToken)
        external
        view
        returns (HorizenPoolInfo memory pool)
    {
        bytes32 poolId = tokenPools[baseToken];
        return pools[poolId];
    }

    /**
     * @dev Get all pools with minimum privacy level
     * @param minPrivacyLevel Minimum privacy level filter
     * @return poolIds Array of qualifying pool IDs
     */
    function getPrivacyPools(uint8 minPrivacyLevel)
        external
        view
        returns (bytes32[] memory poolIds)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (pools[allPools[i]].privacyLevel >= minPrivacyLevel && pools[allPools[i]].isActive) {
                count++;
            }
        }

        poolIds = new bytes32[](count);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (pools[allPools[i]].privacyLevel >= minPrivacyLevel && pools[allPools[i]].isActive) {
                poolIds[currentIndex] = allPools[i];
                currentIndex++;
            }
        }

        return poolIds;
    }

    /**
     * @dev Get developer program statistics
     * @return totalAllocation Total program allocation
     * @return used Amount used so far
     * @return remaining Amount remaining
     */
    function getDeveloperProgramStats()
        external
        view
        returns (
            uint256 totalAllocation,
            uint256 used,
            uint256 remaining
        )
    {
        return (
            DEVELOPER_PROGRAM_TOTAL,
            developerProgramUsed,
            DEVELOPER_PROGRAM_TOTAL - developerProgramUsed
        );
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    function _createPoolInternal(
        PoolCreationParams calldata params,
        bool isSubsidized
    ) internal returns (address poolAddress, address orderbookAddress) {
        bytes32 poolId = _getPoolId(params.baseToken);
        if (pools[poolId].poolAddress != address(0)) revert PoolAlreadyExists();

        // Deploy contracts
        HorizenPrivacyTradingPool pool = new HorizenPrivacyTradingPool(
            params.baseToken,
            zkVerifier,
            singularityIntegration,
            msg.sender
        );
        poolAddress = address(pool);

        ZKOrderbook orderbook = new ZKOrderbook(zkVerifier, poolAddress);
        orderbookAddress = address(orderbook);

        // Store pool info
        pools[poolId] = HorizenPoolInfo({
            poolAddress: poolAddress,
            orderbookAddress: orderbookAddress,
            baseToken: params.baseToken,
            zenToken: address(zenToken),
            creator: msg.sender,
            createdAt: block.timestamp,
            isActive: true,
            name: params.poolName,
            privacyLevel: params.desiredPrivacyLevel,
            zenStaked: params.zenStakeAmount,
            singularityEnabled: params.enableSingularity
        });

        // Update mappings
        userPools[msg.sender].push(poolId);
        tokenPools[params.baseToken] = poolId;
        allPools.push(poolId);

        if (!isSubsidized) {
            totalZENLocked += params.zenStakeAmount;
        }

        emit HorizenPoolCreated(
            poolId,
            msg.sender,
            poolAddress,
            orderbookAddress,
            params.baseToken,
            params.desiredPrivacyLevel,
            params.zenStakeAmount,
            params.poolName
        );

        return (poolAddress, orderbookAddress);
    }

    function _getPoolId(address baseToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(baseToken));
    }

    function _calculatePrivacyLevel(uint256 zenStaked) internal pure returns (uint8) {
        if (zenStaked >= 10000e18) return 95; // 10k+ ZEN = maximum privacy
        if (zenStaked >= 1000e18) return 85;  // 1k+ ZEN = high privacy
        if (zenStaked >= 100e18) return 75;   // 100+ ZEN = medium privacy
        return 60; // Minimum privacy level
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /**
     * @dev Update pool creation fee
     * @param newFee New creation fee in ZEN
     */
    function setPoolCreationFee(uint256 newFee) external onlyOwner {
        poolCreationFee = newFee;
    }

    /**
     * @dev Emergency withdraw of developer program funds
     * @param amount Amount to withdraw
     */
    function emergencyWithdrawDeveloperFunds(uint256 amount) external onlyOwner {
        require(amount <= DEVELOPER_PROGRAM_TOTAL - developerProgramUsed, "Exceeds available");
        zenToken.transfer(owner(), amount);
    }
}