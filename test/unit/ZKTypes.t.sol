// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "@forge-std/Test.sol";
import {ZKTypes} from "../../src/libraries/ZKTypes.sol";

contract ZKTypesTest is Test {
    function testProofStruct() public {
        ZKTypes.Proof memory proof = ZKTypes.Proof({
            a: [uint256(1), uint256(2)],
            b: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            c: [uint256(7), uint256(8)]
        });
        
        assertEq(proof.a[0], 1);
        assertEq(proof.a[1], 2);
        assertEq(proof.b[0][0], 3);
        assertEq(proof.b[0][1], 4);
        assertEq(proof.b[1][0], 5);
        assertEq(proof.b[1][1], 6);
        assertEq(proof.c[0], 7);
        assertEq(proof.c[1], 8);
    }

    function testTradeCommitmentStruct() public {
        bytes32 commitment = keccak256("test");
        bytes32 nullifier = keccak256("nullifier");
        address trader = makeAddr("trader");
        
        ZKTypes.TradeCommitment memory tradeCommitment = ZKTypes.TradeCommitment({
            commitment: commitment,
            timestamp: block.timestamp,
            executed: false,
            nullifierHash: nullifier,
            trader: trader
        });
        
        assertEq(tradeCommitment.commitment, commitment);
        assertEq(tradeCommitment.timestamp, block.timestamp);
        assertFalse(tradeCommitment.executed);
        assertEq(tradeCommitment.nullifierHash, nullifier);
        assertEq(tradeCommitment.trader, trader);
    }
}