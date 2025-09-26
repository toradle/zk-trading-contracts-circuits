// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title HorizenConfig
 * @dev Configuration constants for Horizen network integration
 * @notice Contains addresses and constants for Horizen L3 privacy stack on Base
 */
library HorizenConfig {
    // =============================================================================
    // ZEN TOKEN ADDRESSES
    // =============================================================================

    /// @dev ZEN token address on Base Mainnet
    address public constant ZEN_MAINNET = 0xf43eB8De897Fbc7F2502483B2Bef7Bb9EA179229;

    /// @dev ZEN token address on Base Sepolia Testnet
    address public constant ZEN_TESTNET = 0x107fdE93838e3404934877935993782F977324BB;

    // =============================================================================
    // NETWORK CONFIGURATION
    // =============================================================================

    /// @dev Base Mainnet Chain ID
    uint256 public constant BASE_MAINNET_CHAIN_ID = 8453;

    /// @dev Base Sepolia Chain ID
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    /// @dev Horizen Testnet Chain ID (Base compatible)
    uint256 public constant HORIZEN_TESTNET_CHAIN_ID = 84532;

    // =============================================================================
    // RPC ENDPOINTS
    // =============================================================================

    /// @dev Horizen Testnet RPC URL
    string public constant HORIZEN_TESTNET_RPC = "https://horizen-rpc-testnet.appchain.base.org";

    /// @dev Base Mainnet RPC URL
    string public constant BASE_MAINNET_RPC = "https://mainnet.base.org";

    /// @dev Base Sepolia RPC URL
    string public constant BASE_SEPOLIA_RPC = "https://sepolia.base.org";

    // =============================================================================
    // HORIZEN L3 PRIVACY STACK CONSTANTS
    // =============================================================================

    /// @dev Default privacy level for Horizen transactions (0-100, 100 = maximum privacy)
    uint8 public constant DEFAULT_PRIVACY_LEVEL = 80;

    /// @dev Minimum commitment time for private trades (prevents MEV)
    uint256 public constant MIN_COMMITMENT_TIME = 15 seconds;

    /// @dev Maximum commitment time before expiration
    uint256 public constant MAX_COMMITMENT_TIME = 1 hours;

    // =============================================================================
    // SINGULARITY INTEGRATION CONSTANTS
    // =============================================================================

    /// @dev Singularity privacy key length
    uint256 public constant SINGULARITY_KEY_LENGTH = 32;

    /// @dev Default ZK proof verification timeout
    uint256 public constant ZK_PROOF_TIMEOUT = 5 minutes;

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @dev Returns the appropriate ZEN token address for the current chain
     * @return zen ZEN token address for current network
     */
    function getZENAddress() internal view returns (address zen) {
        uint256 chainId = block.chainid;
        if (chainId == BASE_MAINNET_CHAIN_ID) {
            return ZEN_MAINNET;
        } else if (chainId == BASE_SEPOLIA_CHAIN_ID) {
            return ZEN_TESTNET;
        } else {
            revert("Unsupported network for Horizen integration");
        }
    }

    /**
     * @dev Checks if current network supports Horizen features
     * @return supported True if network is supported
     */
    function isHorizenSupported() internal view returns (bool supported) {
        uint256 chainId = block.chainid;
        return chainId == BASE_MAINNET_CHAIN_ID ||
               chainId == BASE_SEPOLIA_CHAIN_ID ||
               chainId == HORIZEN_TESTNET_CHAIN_ID;
    }

    /**
     * @dev Returns network name for the current chain
     * @return name Network name string
     */
    function getNetworkName() internal view returns (string memory name) {
        uint256 chainId = block.chainid;
        if (chainId == BASE_MAINNET_CHAIN_ID) {
            return "Base Mainnet";
        } else if (chainId == BASE_SEPOLIA_CHAIN_ID || chainId == HORIZEN_TESTNET_CHAIN_ID) {
            return "Horizen Testnet";
        } else {
            return "Unsupported Network";
        }
    }
}