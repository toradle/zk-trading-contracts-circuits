// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ISingularityIntegration
 * @dev Interface for Horizen's Singularity privacy integration
 * @notice Provides stealth-enabled trading capabilities through Singularity partnership
 */
interface ISingularityIntegration {
    // =============================================================================
    // STRUCTS
    // =============================================================================

    struct PrivacyProfile {
        bytes32 privacyKey;          // Singularity privacy key
        uint8 privacyLevel;          // Privacy level (0-100)
        bool stealthMode;            // Stealth transaction mode enabled
        uint256 createdAt;           // Profile creation timestamp
        bool isActive;               // Profile activation status
    }

    struct StealthTransaction {
        bytes32 txHash;              // Original transaction hash
        bytes32 stealthId;           // Stealth identifier
        address from;                // Sender address (encrypted)
        address to;                  // Receiver address (encrypted)
        uint256 amount;              // Amount (encrypted)
        uint256 timestamp;           // Transaction timestamp
        bool isPrivate;              // Privacy flag
    }

    // =============================================================================
    // EVENTS
    // =============================================================================

    event PrivacyProfileCreated(
        address indexed user,
        bytes32 indexed privacyKey,
        uint8 privacyLevel
    );

    event StealthModeEnabled(address indexed user, bytes32 privacyKey);
    event StealthModeDisabled(address indexed user);

    event StealthTransactionExecuted(
        bytes32 indexed stealthId,
        address indexed user,
        uint256 amount,
        bool isPrivate
    );

    event PrivacyLevelUpdated(
        address indexed user,
        uint8 oldLevel,
        uint8 newLevel
    );

    // =============================================================================
    // FUNCTIONS
    // =============================================================================

    /**
     * @dev Creates a new privacy profile with Singularity integration
     * @param privacyKey Unique privacy key for the user
     * @param privacyLevel Desired privacy level (0-100)
     * @return success True if profile created successfully
     */
    function createPrivacyProfile(
        bytes32 privacyKey,
        uint8 privacyLevel
    ) external returns (bool success);

    /**
     * @dev Enables stealth mode for user transactions
     * @param privacyKey User's privacy key
     * @return success True if stealth mode enabled
     */
    function enableStealthMode(bytes32 privacyKey) external returns (bool success);

    /**
     * @dev Disables stealth mode for user transactions
     * @return success True if stealth mode disabled
     */
    function disableStealthMode() external returns (bool success);

    /**
     * @dev Executes a stealth transaction through Singularity
     * @param to Recipient address (encrypted)
     * @param amount Transaction amount (encrypted)
     * @param data Transaction data (encrypted)
     * @return stealthId Unique stealth transaction identifier
     */
    function executeStealthTransaction(
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes32 stealthId);

    /**
     * @dev Updates privacy level for existing profile
     * @param newPrivacyLevel New privacy level (0-100)
     * @return success True if privacy level updated
     */
    function updatePrivacyLevel(uint8 newPrivacyLevel) external returns (bool success);

    /**
     * @dev Gets user's privacy profile
     * @param user User address
     * @return profile User's privacy profile
     */
    function getPrivacyProfile(address user) external view returns (PrivacyProfile memory profile);

    /**
     * @dev Checks if user has stealth mode enabled
     * @param user User address
     * @return enabled True if stealth mode is active
     */
    function isStealthModeEnabled(address user) external view returns (bool enabled);

    /**
     * @dev Gets stealth transaction details
     * @param stealthId Stealth transaction ID
     * @return transaction Stealth transaction details
     */
    function getStealthTransaction(
        bytes32 stealthId
    ) external view returns (StealthTransaction memory transaction);

    /**
     * @dev Verifies if transaction is eligible for privacy protection
     * @param txHash Transaction hash to verify
     * @return eligible True if transaction can use privacy features
     */
    function isPrivacyEligible(bytes32 txHash) external view returns (bool eligible);
}