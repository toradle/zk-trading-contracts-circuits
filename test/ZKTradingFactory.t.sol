// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "@forge-std/Test.sol";
import {MockZKVerifier} from "../src/mocks/MockZKVerifier.sol";
import {TestERC20} from "../src/mocks/TestERC20.sol";
import {ZKTradingFactory} from "../src/ZKTradingFactory.sol";
import {ZKTradingPool} from "../src/ZKTradingPool.sol";
import {ZKOrderbook} from "../src/ZKOrderbook.sol";

contract ZKTradingFactoryTest is Test {
    MockZKVerifier public zkVerifier;
    TestERC20 public zenToken;
    TestERC20 public usdcToken;
    ZKTradingFactory public factory;

    address public owner;
    address public user1;
    address public user2;
    address public feeRecipient;

    event PoolCreated(
        bytes32 indexed poolId,
        address indexed creator,
        address poolAddress,
        address orderbookAddress,
        address baseToken,
        address quoteToken,
        string name
    );

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        feeRecipient = makeAddr("feeRecipient");

        // Deploy contracts
        zkVerifier = new MockZKVerifier();
        zenToken = new TestERC20("Horizen", "ZEN", 18, 1000000 * 10**18);
        usdcToken = new TestERC20("USD Coin", "USDC", 6, 1000000 * 10**6);
        
        factory = new ZKTradingFactory(address(zkVerifier), feeRecipient);

        // Fund users for pool creation fees
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
    }

    function testDeployment() public view {
        assertEq(factory.zkVerifier(), address(zkVerifier));
        assertEq(factory.feeRecipient(), feeRecipient);
        assertEq(factory.owner(), owner);
        assertGt(factory.poolCreationFee(), 0);
    }

    function testCreateTradingPool() public {
        string memory poolName = "ZEN/USDC Pool";
        uint256 creationFee = factory.poolCreationFee();
        
        bytes32 expectedPoolId = factory.getPoolId(address(zenToken), address(usdcToken));
        
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(
            expectedPoolId,
            user1,
            address(0), // Will be filled by actual deployment
            address(0), // Will be filled by actual deployment
            address(zenToken),
            address(usdcToken),
            poolName
        );
        
        vm.prank(user1);
        (address poolAddress, address orderbookAddress) = factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            poolName
        );
        
        // Verify pool was created
        assertTrue(poolAddress != address(0));
        assertTrue(orderbookAddress != address(0));
        
        // Verify pool info
        ZKTradingFactory.PoolInfo memory poolInfo = factory.pools(expectedPoolId);
        assertEq(poolInfo.poolAddress, poolAddress);
        assertEq(poolInfo.orderbookAddress, orderbookAddress);
        assertEq(poolInfo.baseToken, address(zenToken));
        assertEq(poolInfo.quoteToken, address(usdcToken));
        assertEq(poolInfo.creator, user1);
        assertTrue(poolInfo.isActive);
        
        // Verify mappings
        bytes32[] memory userPools = factory.getUserPools(user1);
        assertEq(userPools.length, 1);
        assertEq(userPools[0], expectedPoolId);
        
        ZKTradingFactory.PoolInfo memory poolByTokens = factory.getPoolByTokens(address(zenToken), address(usdcToken));
        assertEq(poolByTokens.poolAddress, poolAddress);
    }

    function testCreateTradingPoolInsufficientFee() public {
        uint256 insufficientFee = factory.poolCreationFee() - 1;
        
        vm.prank(user1);
        vm.expectRevert(ZKTradingFactory.InsufficientFee.selector);
        factory.createTradingPool{value: insufficientFee}(
            address(zenToken),
            address(usdcToken),
            "Test Pool"
        );
    }

    function testCreateTradingPoolIdenticalTokens() public {
        uint256 creationFee = factory.poolCreationFee();
        
        vm.prank(user1);
        vm.expectRevert(ZKTradingFactory.IdenticalTokens.selector);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(zenToken),
            "Invalid Pool"
        );
    }

    function testCreateTradingPoolAlreadyExists() public {
        uint256 creationFee = factory.poolCreationFee();
        
        // Create first pool
        vm.prank(user1);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "First Pool"
        );
        
        // Try to create duplicate
        vm.prank(user2);
        vm.expectRevert(ZKTradingFactory.PoolAlreadyExists.selector);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "Duplicate Pool"
        );
    }

    function testDeactivatePool() public {
        uint256 creationFee = factory.poolCreationFee();
        
        // Create pool
        vm.prank(user1);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "Test Pool"
        );
        
        bytes32 poolId = factory.getPoolId(address(zenToken), address(usdcToken));
        
        // Deactivate pool
        vm.prank(user1);
        factory.deactivatePool(poolId);
        
        // Verify pool is deactivated
        ZKTradingFactory.PoolInfo memory poolInfo = factory.pools(poolId);
        assertFalse(poolInfo.isActive);
    }

    function testDeactivatePoolUnauthorized() public {
        uint256 creationFee = factory.poolCreationFee();
        
        // Create pool
        vm.prank(user1);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "Test Pool"
        );
        
        bytes32 poolId = factory.getPoolId(address(zenToken), address(usdcToken));
        
        // Try to deactivate from unauthorized account
        vm.prank(user2);
        vm.expectRevert(ZKTradingFactory.UnauthorizedDeactivation.selector);
        factory.deactivatePool(poolId);
    }

    function testGetActivePools() public {
        uint256 creationFee = factory.poolCreationFee();
        
        // Create two pools
        vm.prank(user1);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "Pool 1"
        );
        
        TestERC20 daiToken = new TestERC20("DAI", "DAI", 18, 1000000 * 10**18);
        vm.prank(user2);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(daiToken),
            "Pool 2"
        );
        
        // Deactivate one pool
        bytes32 poolId1 = factory.getPoolId(address(zenToken), address(usdcToken));
        vm.prank(user1);
        factory.deactivatePool(poolId1);
        
        // Check active pools
        bytes32[] memory activePools = factory.getActivePools();
        assertEq(activePools.length, 1);
        
        bytes32[] memory allPools = factory.getAllPools();
        assertEq(allPools.length, 2);
    }

    function testSetPoolCreationFee() public {
        uint256 newFee = 0.05 ether;
        
        factory.setPoolCreationFee(newFee);
        assertEq(factory.poolCreationFee(), newFee);
    }

    function testSetProtocolFee() public {
        uint256 newFee = 200; // 2%
        
        factory.setProtocolFee(newFee);
        assertEq(factory.protocolFee(), newFee);
    }

    function testSetProtocolFeeTooHigh() public {
        uint256 tooHighFee = 1100; // 11%
        
        vm.expectRevert(ZKTradingFactory.FeeTooHigh.selector);
        factory.setProtocolFee(tooHighFee);
    }

    function testSetFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        
        factory.setFeeRecipient(newRecipient);
        assertEq(factory.feeRecipient(), newRecipient);
    }

    function testWithdrawFees() public {
        uint256 creationFee = factory.poolCreationFee();
        
        // Create pool to generate fees
        vm.prank(user1);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "Test Pool"
        );
        
        uint256 feeRecipientBalanceBefore = feeRecipient.balance;
        
        // Withdraw fees
        factory.withdrawFees();
        
        assertEq(feeRecipient.balance - feeRecipientBalanceBefore, creationFee);
        assertEq(address(factory).balance, 0);
    }

    function testGetTotalPools() public {
        assertEq(factory.getTotalPools(), 0);
        
        uint256 creationFee = factory.poolCreationFee();
        
        // Create pool
        vm.prank(user1);
        factory.createTradingPool{value: creationFee}(
            address(zenToken),
            address(usdcToken),
            "Test Pool"
        );
        
        assertEq(factory.getTotalPools(), 1);
    }
}