// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IZEN
 * @dev Interface for ZEN token on Base network
 * @notice ZEN token deployed on Base L2 as part of Horizen 2.0 migration
 */
interface IZEN is IERC20 {
    /**
     * @dev Returns the ZEN token contract address on Base Mainnet
     * Mainnet: 0xf43eB8De897Fbc7F2502483B2Bef7Bb9EA179229
     * Base Sepolia: 0x107fdE93838e3404934877935993782F977324BB
     */

    /**
     * @dev ZEN-specific functions if any additional methods are available
     * Note: Since ZEN is now an ERC-20 on Base, it follows standard ERC-20 interface
     */

    // Additional ZEN-specific events
    event HorizenPrivacyEnabled(address indexed user, bool enabled);
    event SingularityIntegration(address indexed user, bytes32 privacyKey);
}