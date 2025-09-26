// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "@forge-std/Test.sol";
import {MockZKVerifier} from "../src/mocks/MockZKVerifier.sol";
import {TestERC20} from "../src/mocks/TestERC20.sol";
import {ZKTradingPool} from "../src/ZKTradingPool.sol";
import {ZKTypes} from "../src/libraries/ZKTypes.sol";

contract ZKTradingPoolTest is Test {
    MockZKVerifier public zkVerifier;
    TestERC20 public zenToken;
    TestERC20 public usdcToken;
    ZKTradingPool public tradingPool;

    address public owner;
    address public trader1;
    address public trader2;

    uint256 constant INITIAL_BALANCE = 1000 * 10**18;
    uint256 constant INITIAL_USDC = 10000 * 10**6;

    event CommitmentMade(bytes32 indexed commitment, address indexed user, uint256 timestamp);
    event TradeExecuted(
        bytes32 indexed commitment,
        address indexed trader,
        uint256 amount,
        uint256 price,
        bool isBuyOrder
    );

    function setUp() public {
        owner = address(this);
        trader1 = makeAddr("trader1");
        trader2 = makeAddr("trader2");

        // Deploy contracts
        zkVerifier = new MockZKVerifier();
        zenToken = new TestERC20("Horizen", "ZEN", 18, INITIAL_BALANCE * 10);
        usdcToken = new TestERC20("USD Coin", "USDC", 6, INITIAL_USDC * 10);
        
        tradingPool = new ZKTradingPool(
            address(zenToken),
            address(usdcToken),
            address(zkVerifier),
            owner
        );

        // Setup test accounts
        zenToken.transfer(trader1, INITIAL_BALANCE);
        zenToken.transfer(trader2, INITIAL_BALANCE);
        usdcToken.transfer(trader1, INITIAL_USDC);
        usdcToken.transfer(trader2, INITIAL_USDC);

        // Approve trading pool
        vm.prank(trader1);
        zenToken.approve(address(tradingPool), type(uint256).max);
        vm.prank(trader1);
        usdcToken.approve(address(tradingPool), type(uint256).max);

        vm.prank(trader2);
        zenToken.approve(address(tradingPool), type(uint256).max);
        vm.prank(trader2);
        usdcToken.approve(address(tradingPool), type(uint256).max);
    }

    function testDeployment() public view {
        assertEq(address(tradingPool.baseToken()), address(zenToken));
        assertEq(address(tradingPool.quoteToken()), address(usdcToken));
        assertEq(address(tradingPool.zkVerifier()), address(zkVerifier));
        assertEq(tradingPool.owner(), owner);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 * 10**18;
        
        vm.prank(trader1);
        tradingPool.deposit(address(zenToken), depositAmount);
        
        assertEq(tradingPool.balances(trader1), depositAmount);
        assertEq(zenToken.balanceOf(address(tradingPool)), depositAmount);
    }

    function testDepositInvalidToken() public {
        TestERC20 invalidToken = new TestERC20("Invalid", "INV", 18, 1000 * 10**18);
        
        vm.prank(trader1);
        vm.expectRevert(ZKTradingPool.InvalidToken.selector);
        tradingPool.deposit(address(invalidToken), 100 * 10**18);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 * 10**18;
        uint256 withdrawAmount = 50 * 10**18;
        
        // Deposit first
        vm.prank(trader1);
        tradingPool.deposit(address(zenToken), depositAmount);
        
        // Withdraw
        vm.prank(trader1);
        tradingPool.withdraw(address(zenToken), withdrawAmount);
        
        assertEq(tradingPool.balances(trader1), depositAmount - withdrawAmount);
    }

    function testMakeCommitment() public {
        bytes32 commitment = keccak256("test commitment");
        
        vm.expectEmit(true, true, false, true);
        emit CommitmentMade(commitment, trader1, block.timestamp);
        
        vm.prank(trader1);
        tradingPool.makeCommitment(commitment);
        
        ZKTypes.TradeCommitment memory storedCommitment = tradingPool.getCommitment(commitment);
        assertEq(storedCommitment.commitment, commitment);
        assertEq(storedCommitment.trader, trader1);
        assertEq(storedCommitment.timestamp, block.timestamp);
        assertFalse(storedCommitment.executed);
    }

    function testMakeCommitmentTwice() public {
        bytes32 commitment = keccak256("test commitment");
        
        vm.prank(trader1);
        tradingPool.makeCommitment(commitment);
        
        vm.prank(trader1);
        vm.expectRevert(ZKTradingPool.CommitmentAlreadyExists.selector);
        tradingPool.makeCommitment(commitment);
    }

    function testExecutePrivateTradeBeforeCommitmentPhase() public {
        bytes32 commitment = keccak256("test commitment");
        bytes32 nullifierHash = keccak256("test nullifier");
        
        vm.prank(trader1);
        tradingPool.makeCommitment(commitment);
        
        ZKTypes.Proof memory proof = ZKTypes.Proof({
            a: [uint256(1), uint256(2)],
            b: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            c: [uint256(7), uint256(8)]
        });
        
        vm.prank(trader1);
        vm.expectRevert(ZKTradingPool.CommitmentNotReady.selector);
        tradingPool.executePrivateTrade(
            commitment,
            proof,
            nullifierHash,
            100 * 10**18,
            2000 * 10**18,
            true
        );
    }

    function testExecutePrivateTrade() public {
        bytes32 commitment = keccak256("test commitment");
        bytes32 nullifierHash = keccak256("test nullifier");
        uint256 tradeAmount = 100 * 10**18;
        uint256 tradePrice = 2000 * 10**18;
        
        // Deposit USDC for buy order
        vm.prank(trader1);
        tradingPool.deposit(address(usdcToken), 2100 * 10**6); // Enough for trade + fees
        
        // Make commitment
        vm.prank(trader1);
        tradingPool.makeCommitment(commitment);
        
        // Fast forward past commitment phase
        vm.warp(block.timestamp + tradingPool.COMMITMENT_PHASE_DURATION() + 1);
        
        ZKTypes.Proof memory proof = ZKTypes.Proof({
            a: [uint256(1), uint256(2)],
            b: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            c: [uint256(7), uint256(8)]
        });
        
        // Execute trade
        vm.expectEmit(true, true, false, true);
        emit TradeExecuted(commitment, trader1, tradeAmount, tradePrice, true);
        
        vm.prank(trader1);
        tradingPool.executePrivateTrade(
            commitment,
            proof,
            nullifierHash,
            tradeAmount,
            tradePrice,
            true // buy order
        );
        
        // Verify commitment is executed
        ZKTypes.TradeCommitment memory storedCommitment = tradingPool.getCommitment(commitment);
        assertTrue(storedCommitment.executed);
        assertEq(storedCommitment.nullifierHash, nullifierHash);
        
        // Verify nullifier is used
        assertTrue(tradingPool.nullifierHashes(nullifierHash));
    }

    function testExecutePrivateTradeInsufficientBalance() public {
        bytes32 commitment = keccak256("test commitment");
        bytes32 nullifierHash = keccak256("test nullifier");
        
        // Make commitment without depositing enough balance
        vm.prank(trader1);
        tradingPool.makeCommitment(commitment);
        
        vm.warp(block.timestamp + tradingPool.COMMITMENT_PHASE_DURATION() + 1);
        
        ZKTypes.Proof memory proof = ZKTypes.Proof({
            a: [uint256(1), uint256(2)],
            b: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            c: [uint256(7), uint256(8)]
        });
        
        vm.prank(trader1);
        vm.expectRevert(ZKTradingPool.InsufficientBalance.selector);
        tradingPool.executePrivateTrade(
            commitment,
            proof,
            nullifierHash,
            100 * 10**18,
            2000 * 10**18,
            true
        );
    }

    function testCreatePrivateOrder() public {
        bytes32 orderHash = keccak256("test order");
        bytes32 encryptedAmount = keccak256("encrypted amount");
        bytes32 encryptedPrice = keccak256("encrypted price");
        
        ZKTypes.Proof memory proof = ZKTypes.Proof({
            a: [uint256(1), uint256(2)],
            b: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            c: [uint256(7), uint256(8)]
        });
        
        vm.prank(trader1);
        tradingPool.createPrivateOrder(
            proof,
            orderHash,
            encryptedAmount,
            encryptedPrice,
            true // buy order
        );
        
        ZKTypes.PrivateOrder memory order = tradingPool.getPrivateOrder(orderHash);
        assertEq(order.orderHash, orderHash);
        assertEq(order.trader, trader1);
        assertTrue(order.isBuyOrder);
        assertFalse(order.filled);
    }

    function testSetTradingFee() public {
        uint256 newFee = 50; // 0.5%
        
        tradingPool.setTradingFee(newFee);
        assertEq(tradingPool.tradingFee(), newFee);
    }

    function testSetTradingFeeTooHigh() public {
        uint256 tooHighFee = 1100; // 11%
        
        vm.expectRevert(ZKTradingPool.FeeTooHigh.selector);
        tradingPool.setTradingFee(tooHighFee);
    }

    function testPauseAndUnpause() public {
        tradingPool.pause();
        assertTrue(tradingPool.paused());
        
        bytes32 commitment = keccak256("test commitment");
        
        vm.prank(trader1);
        vm.expectRevert("Pausable: paused");
        tradingPool.makeCommitment(commitment);
        
        tradingPool.unpause();
        assertFalse(tradingPool.paused());
        
        vm.prank(trader1);
        tradingPool.makeCommitment(commitment);
    }

    function testGetNonceAndIncrement() public {
        assertEq(tradingPool.getNonce(trader1), 0);
        
        vm.prank(trader1);
        tradingPool.incrementNonce();
        
        assertEq(tradingPool.getNonce(trader1), 1);
    }

    function testBatchProcessZKProofs() public {
        uint256 batchSize = 3;
        bytes32[] memory commitments = new bytes32[](batchSize);
        ZKTypes.Proof[] memory proofs = new ZKTypes.Proof[](batchSize);
        bytes32[] memory nullifiers = new bytes32[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);
        uint256[] memory prices = new uint256[](batchSize);
        bool[] memory isBuyOrders = new bool[](batchSize);
        
        // Setup batch data
        for (uint256 i = 0; i < batchSize; i++) {
            commitments[i] = keccak256(abi.encodePacked("commitment", i));
            proofs[i] = ZKTypes.Proof({
                a: [uint256(i + 1), uint256(i + 2)],
                b: [[uint256(i + 3), uint256(i + 4)], [uint256(i + 5), uint256(i + 6)]],
                c: [uint256(i + 7), uint256(i + 8)]
            });
            nullifiers[i] = keccak256(abi.encodePacked("nullifier", i));
            amounts[i] = (i + 1) * 10 * 10**18;
            prices[i] = (i + 1) * 1000 * 10**18;
            isBuyOrders[i] = true;
        }
        
        // Make commitments and deposit balance
        vm.startPrank(trader1);
        tradingPool.deposit(address(usdcToken), 10000 * 10**6);
        
        for (uint256 i = 0; i < batchSize; i++) {
            tradingPool.makeCommitment(commitments[i]);
        }
        vm.stopPrank();
        
        // Fast forward
        vm.warp(block.timestamp + tradingPool.COMMITMENT_PHASE_DURATION() + 1);
        
        // Execute batch
        vm.prank(trader1);
        tradingPool.batchProcessZKProofs(
            commitments,
            proofs,
            nullifiers,
            amounts,
            prices,
            isBuyOrders
        );
        
        // Verify all commitments are executed
        for (uint256 i = 0; i < batchSize; i++) {
            assertTrue(tradingPool.getCommitment(commitments[i]).executed);
            assertTrue(tradingPool.nullifierHashes(nullifiers[i]));
        }
    }

    function testUpdateMerkleRoot() public {
        bytes32 newRoot = keccak256("new merkle root");
        
        tradingPool.updateMerkleRoot(newRoot);
        assertEq(tradingPool.merkleRoot(), newRoot);
    }

    function testEmergencyWithdraw() public {
        uint256 amount = 100 * 10**18;
        
        // Deposit some tokens to the contract
        vm.prank(trader1);
        tradingPool.deposit(address(zenToken), amount);
        
        // Pause and emergency withdraw
        tradingPool.pause();
        
        uint256 ownerBalanceBefore = zenToken.balanceOf(owner);
        tradingPool.emergencyWithdraw(address(zenToken), amount);
        
        assertEq(zenToken.balanceOf(owner) - ownerBalanceBefore, amount);
    }
}