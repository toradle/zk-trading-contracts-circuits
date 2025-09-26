// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library ZKTypes {
    struct Proof {
        uint[2] a;
        uint[2][2] b;
        uint[2] c;
    }

    struct TradeCommitment {
        bytes32 commitment;
        uint256 timestamp;
        bool executed;
        bytes32 nullifierHash;
        address trader;
    }

    struct PrivateOrder {
        bytes32 orderHash;
        bytes32 encryptedAmount;
        bytes32 encryptedPrice;
        address trader;
        bool isBuyOrder;
        uint256 timestamp;
        bool filled;
        uint256 executedAmount;
        uint256 executedPrice;
    }

    struct OrderMatch {
        bytes32 buyOrderId;
        bytes32 sellOrderId;
        bytes32 matchCommitment;
        uint256 timestamp;
        bool executed;
        uint256 amount;
        uint256 price;
    }

    struct BalanceProof {
        bytes32 root;
        bytes32 nullifierHash;
        uint256 amount;
        bytes32[] merkleProof;
    }
}