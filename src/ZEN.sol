// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IZEN.sol";

/**
 * @title ZEN
 * @dev Official ZEN token implementation on Base network
 * @notice Migrated from Horizen mainchain to Base L2 as part of Horizen 2.0
 *
 * Contract Addresses:
 * - Base Mainnet: 0xf43eB8De897Fbc7F2502483B2Bef7Bb9EA179229
 * - Base Sepolia: 0x107fdE93838e3404934877935993782F977324BB
 */
contract ZEN is ERC20, Ownable, Pausable, IZEN {
    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @dev ZEN has 18 decimals
    uint8 private constant DECIMALS = 18;

    /// @dev Maximum total supply (21M ZEN)
    uint256 public constant MAX_SUPPLY = 21_000_000 * 10**DECIMALS;

    /// @dev Migration period duration (for claiming from old chain)
    uint256 public constant MIGRATION_PERIOD = 365 days;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    /// @dev Migration start timestamp
    uint256 public immutable migrationStartTime;

    /// @dev Mapping of migrated amounts from old chain
    mapping(address => uint256) public migratedAmounts;

    /// @dev Total amount migrated so far
    uint256 public totalMigrated;

    /// @dev Migration enabled flag
    bool public migrationEnabled = true;

    // Horizen-specific features
    mapping(address => bool) private _privacyEnabled;
    mapping(address => bytes32) private _singularityKeys;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event TokensMigrated(address indexed user, uint256 amount, bytes32 oldChainTxHash);
    event MigrationEnabled(bool enabled);

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {
        require(initialSupply <= MAX_SUPPLY, "Initial supply exceeds maximum");
        require(initialOwner != address(0), "Invalid owner address");

        migrationStartTime = block.timestamp;

        // Mint initial supply to owner for migration distribution
        if (initialSupply > 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    // =============================================================================
    // MIGRATION FUNCTIONS
    // =============================================================================

    /**
     * @dev Migrate ZEN tokens from old Horizen chain
     * @param user Address to receive migrated tokens
     * @param amount Amount of ZEN to migrate
     * @param oldChainTxHash Transaction hash from old chain as proof
     */
    function migrateFromOldChain(
        address user,
        uint256 amount,
        bytes32 oldChainTxHash
    ) external onlyOwner {
        require(migrationEnabled, "Migration disabled");
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Invalid amount");
        require(oldChainTxHash != bytes32(0), "Invalid transaction hash");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds maximum supply");

        // Record migration
        migratedAmounts[user] += amount;
        totalMigrated += amount;

        // Mint migrated tokens
        _mint(user, amount);

        emit TokensMigrated(user, amount, oldChainTxHash);
    }

    /**
     * @dev Batch migrate multiple users (gas efficient)
     * @param users Array of user addresses
     * @param amounts Array of amounts to migrate
     * @param oldChainTxHashes Array of old chain transaction hashes
     */
    function batchMigrate(
        address[] calldata users,
        uint256[] calldata amounts,
        bytes32[] calldata oldChainTxHashes
    ) external onlyOwner {
        require(migrationEnabled, "Migration disabled");
        require(
            users.length == amounts.length && amounts.length == oldChainTxHashes.length,
            "Array length mismatch"
        );

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(totalSupply() + totalAmount <= MAX_SUPPLY, "Exceeds maximum supply");

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid user address");
            require(amounts[i] > 0, "Invalid amount");
            require(oldChainTxHashes[i] != bytes32(0), "Invalid transaction hash");

            migratedAmounts[users[i]] += amounts[i];
            totalMigrated += amounts[i];

            _mint(users[i], amounts[i]);

            emit TokensMigrated(users[i], amounts[i], oldChainTxHashes[i]);
        }
    }

    // =============================================================================
    // HORIZEN PRIVACY FEATURES
    // =============================================================================

    /**
     * @dev Enable Horizen privacy features for user
     * @param privacyKey Singularity privacy key
     */
    function enableHorizenPrivacy(bytes32 privacyKey) external {
        require(privacyKey != bytes32(0), "Invalid privacy key");

        _privacyEnabled[msg.sender] = true;
        _singularityKeys[msg.sender] = privacyKey;

        emit HorizenPrivacyEnabled(msg.sender, true);
    }

    /**
     * @dev Disable Horizen privacy features for user
     */
    function disableHorizenPrivacy() external {
        _privacyEnabled[msg.sender] = false;
        delete _singularityKeys[msg.sender];

        emit HorizenPrivacyEnabled(msg.sender, false);
    }

    /**
     * @dev Check if privacy is enabled for user
     * @param user User address to check
     * @return enabled True if privacy is enabled
     */
    function isPrivacyEnabled(address user) external view returns (bool enabled) {
        return _privacyEnabled[user];
    }

    /**
     * @dev Get user's Singularity integration key
     * @param user User address
     * @return privacyKey User's privacy key (returns 0 if not set or unauthorized)
     */
    function getSingularityKey(address user) external view returns (bytes32 privacyKey) {
        require(msg.sender == user || msg.sender == owner(), "Unauthorized");
        return _singularityKeys[user];
    }

    /**
     * @dev Private transfer with Singularity integration
     * @param to Recipient address
     * @param amount Amount to transfer
     * @param usePrivacy Use privacy features
     * @return success Transfer success
     */
    function privateTransfer(
        address to,
        uint256 amount,
        bool usePrivacy
    ) external returns (bool success) {
        if (usePrivacy && _privacyEnabled[msg.sender]) {
            emit SingularityIntegration(msg.sender, _singularityKeys[msg.sender]);
        }

        return transfer(to, amount);
    }

    // =============================================================================
    // GOVERNANCE FUNCTIONS
    // =============================================================================

    /**
     * @dev Toggle migration functionality
     * @param enabled True to enable migration, false to disable
     */
    function setMigrationEnabled(bool enabled) external onlyOwner {
        migrationEnabled = enabled;
        emit MigrationEnabled(enabled);
    }

    /**
     * @dev Emergency mint (only during migration period)
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function emergencyMint(address to, uint256 amount) external onlyOwner {
        require(
            block.timestamp <= migrationStartTime + MIGRATION_PERIOD,
            "Migration period ended"
        );
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds maximum supply");

        _mint(to, amount);
    }

    /**
     * @dev Pause contract (emergency only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================================
    // OVERRIDES
    // =============================================================================

    /**
     * @dev Override decimals to return 18
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @dev Override transfer to include pause functionality
     */
    function transfer(address to, uint256 amount)
        public
        override(ERC20, IERC20)
        whenNotPaused
        returns (bool)
    {
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to include pause functionality
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override(ERC20, IERC20)
        whenNotPaused
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @dev Get migration statistics
     * @return migrationStart Migration start timestamp
     * @return migrationEnd Migration end timestamp
     * @return totalMigratedAmount Total amount migrated
     * @return migrationActive Whether migration is currently active
     */
    function getMigrationInfo()
        external
        view
        returns (
            uint256 migrationStart,
            uint256 migrationEnd,
            uint256 totalMigratedAmount,
            bool migrationActive
        )
    {
        return (
            migrationStartTime,
            migrationStartTime + MIGRATION_PERIOD,
            totalMigrated,
            migrationEnabled && block.timestamp <= migrationStartTime + MIGRATION_PERIOD
        );
    }

    /**
     * @dev Get user's migration history
     * @param user User address
     * @return migratedAmount Amount migrated by user
     */
    function getUserMigrationInfo(address user)
        external
        view
        returns (uint256 migratedAmount)
    {
        return migratedAmounts[user];
    }
}