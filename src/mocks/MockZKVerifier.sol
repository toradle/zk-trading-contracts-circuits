// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IZKVerifier.sol";

/**
 * @title MockZKVerifier
 * @dev Mock ZK verifier for testing purposes
 */
contract MockZKVerifier is IZKVerifier {
    mapping(bytes32 => bool) public validProofs;
    address public owner;
    bool public alwaysValid;

    event ProofVerified(bytes32 indexed proofHash, bool result);
    event ValidProofAdded(bytes32 indexed proofHash);
    event ValidProofRemoved(bytes32 indexed proofHash);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        alwaysValid = true; // For testing, always return true initially
    }

    /**
     * @dev Verify a ZK proof (mock implementation)
     */
    function verifyProof(
        uint[2] memory, // a
        uint[2][2] memory, // b
        uint[2] memory, // c
        uint[1] memory input
    ) external view override returns (bool) {
        if (alwaysValid) {
            return true;
        }

        bytes32 proofHash = keccak256(abi.encodePacked(input[0]));
        return validProofs[proofHash];
    }

    /**
     * @dev Add a valid proof hash for testing
     */
    function addValidProof(bytes32 proofHash) external onlyOwner {
        validProofs[proofHash] = true;
        emit ValidProofAdded(proofHash);
    }

    /**
     * @dev Remove a valid proof hash
     */
    function removeValidProof(bytes32 proofHash) external onlyOwner {
        validProofs[proofHash] = false;
        emit ValidProofRemoved(proofHash);
    }

    /**
     * @dev Set always valid mode (for testing)
     */
    function setAlwaysValid(bool _alwaysValid) external onlyOwner {
        alwaysValid = _alwaysValid;
    }

    /**
     * @dev Transfer ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
    }
}