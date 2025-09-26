// File: script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "@forge-std/Script.sol";
import {MockZKVerifier} from "../src/mocks/MockZKVerifier.sol";
import {TestERC20} from "../src/mocks/TestERC20.sol";
import {ZKTradingFactory} from "../src/ZKTradingFactory.sol";
import {ZKTradingPool} from "../src/ZKTradingPool.sol";
import {ZKOrderbook} from "../src/ZKOrderbook.sol";

/**
 * @title Deploy
 * @dev Deployment script for ZK Trading System
 */
contract Deploy is Script {
    // Deployment configuration
    struct DeployConfig {
        address zkVerifier;
        address zenToken;
        address usdcToken;
        address deployer;
        address feeRecipient;
        uint256 poolCreationFee;
        string poolName;
    }

    // Deployment results
    struct DeploymentResult {
        address zkVerifier;
        address factory;
        address zenToken;
        address usdcToken;
        address tradingPool;
        address orderbook;
        bytes32 poolId;
    }

    DeploymentResult public deploymentResult;

    function setUp() public {}

    /**
     * @dev Main deployment function
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying with address:", deployer);
        console2.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        DeploymentResult memory result = deployFullSystem(deployer);
        
        vm.stopBroadcast();

        // Log deployment results
        logDeploymentResults(result);
        
        // Save deployment info
        saveDeploymentInfo(result);
    }

    /**
     * @dev Deploy the complete ZK trading system
     */
    function deployFullSystem(address deployer) internal returns (DeploymentResult memory) {
        console2.log("\n=== Deploying ZK Trading System ===");
        
        DeploymentResult memory result;
        
        // 1. Deploy ZK Verifier
        console2.log("\n1. Deploying MockZKVerifier...");
        MockZKVerifier zkVerifier = new MockZKVerifier();
        result.zkVerifier = address(zkVerifier);
        console2.log("MockZKVerifier deployed at:", result.zkVerifier);

        // 2. Deploy test tokens
        console2.log("\n2. Deploying test tokens...");
        
        // Deploy ZEN token (18 decimals)
        TestERC20 zenToken = new TestERC20(
            "Horizen",
            "ZEN", 
            18,
            1_000_000 * 10**18 // 1M ZEN
        );
        result.zenToken = address(zenToken);
        console2.log("ZEN Token deployed at:", result.zenToken);

        // Deploy USDC token (6 decimals)
        TestERC20 usdcToken = new TestERC20(
            "USD Coin",
            "USDC",
            6,
            10_000_000 * 10**6 // 10M USDC
        );
        result.usdcToken = address(usdcToken);
        console2.log("USDC Token deployed at:", result.usdcToken);

        // 3. Deploy Factory
        console2.log("\n3. Deploying ZKTradingFactory...");
        ZKTradingFactory factory = new ZKTradingFactory(
            result.zkVerifier,
            deployer // Fee recipient
        );
        result.factory = address(factory);
        console2.log("ZKTradingFactory deployed at:", result.factory);

        // 4. Create trading pool
        console2.log("\n4. Creating ZEN/USDC trading pool...");
        uint256 creationFee = factory.poolCreationFee();
        
        (address poolAddress, address orderbookAddress) = factory.createTradingPool{value: creationFee}(
            result.zenToken,
            result.usdcToken,
            "ZEN/USDC Pool"
        );
        
        result.tradingPool = poolAddress;
        result.orderbook = orderbookAddress;
        result.poolId = factory.getPoolId(result.zenToken, result.usdcToken);
        
        console2.log("ZK Trading Pool deployed at:", result.tradingPool);
        console2.log("ZK Orderbook deployed at:", result.orderbook);
        console2.log("Pool ID:", vm.toString(result.poolId));

        // 5. Setup initial configuration
        console2.log("\n5. Setting up initial configuration...");
        
        // Mint some tokens to deployer for testing
        zenToken.mint(deployer, 10000 * 10**18); // 10K ZEN
        usdcToken.mint(deployer, 50000 * 10**6);  // 50K USDC
        
        console2.log("Minted test tokens to deployer");

        console2.log("\n=== Deployment Complete ===");
        return result;
    }

    /**
     * @dev Log deployment results
     */
    function logDeploymentResults(DeploymentResult memory result) internal view {
        console2.log("\n=== DEPLOYMENT RESULTS ===");
        console2.log("ZK Verifier:      ", result.zkVerifier);
        console2.log("Factory:          ", result.factory);
        console2.log("ZEN Token:        ", result.zenToken);
        console2.log("USDC Token:       ", result.usdcToken);
        console2.log("Trading Pool:     ", result.tradingPool);
        console2.log("Orderbook:        ", result.orderbook);
        console2.log("Pool ID:          ", vm.toString(result.poolId));
        console2.log("==========================");
    }

    /**
     * @dev Save deployment info to file
     */
    function saveDeploymentInfo(DeploymentResult memory result) internal {
        string memory deploymentJson = string.concat(
            '{\n',
            '  "network": "', vm.toString(block.chainid), '",\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "contracts": {\n',
            '    "zkVerifier": "', vm.toString(result.zkVerifier), '",\n',
            '    "factory": "', vm.toString(result.factory), '",\n',
            '    "zenToken": "', vm.toString(result.zenToken), '",\n',
            '    "usdcToken": "', vm.toString(result.usdcToken), '",\n',
            '    "tradingPool": "', vm.toString(result.tradingPool), '",\n',
            '    "orderbook": "', vm.toString(result.orderbook), '",\n',
            '    "poolId": "', vm.toString(result.poolId), '"\n',
            '  }\n',
            '}'
        );
        
        vm.writeFile("./deployments/deployment.json", deploymentJson);
        console2.log("Deployment info saved to ./deployments/deployment.json");
    }
}
