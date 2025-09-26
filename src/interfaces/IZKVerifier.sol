// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IZKVerifier
 * @dev Interface for ZK proof verification using Groth16
 */
interface IZKVerifier {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[1] memory input
    ) external view returns (bool);
}