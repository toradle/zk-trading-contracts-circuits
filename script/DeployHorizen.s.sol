// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console2} from "@forge-std/Script.sol";
import "../src/ZEN.sol";
import "../src/HorizenTradingFactory.sol";
import "../src/HorizenPrivacyTradingPool.sol";
import "../src/ZKOrderbook.sol";
import "../src/mocks/MockZKVerifier.sol";
import "../src/mocks/TestERC20.sol";
import "../src/libraries/HorizenConfig.sol";

/**
 * @title DeployHorizen
 * @dev Deployment script for Horizen ZK Trading system
 * @notice Deploys all contracts to Horizen testnet/mainnet
 */
contract DeployHorizen is Script {
    struct DeploymentResult {
        address zenToken;
        address zkVerifier;
        address singularityIntegration;
        address tradingFactory;
        address testToken;
        string networkName;
        uint256 chainId;
    }

    function setUp() public {}

    /**
     * @dev Main deployment function
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeploymentResult memory result = deployContracts();

        vm.stopBroadcast();

        logDeploymentResults(result);
        generateDeploymentFile(result);
    }

    /**
     * @dev Deploy all Horizen contracts
     */
    function deployContracts() internal returns (DeploymentResult memory result) {
        result.chainId = block.chainid;
        result.networkName = HorizenConfig.getNetworkName();

        console2.log("=== Deploying to:", result.networkName);
        console2.log("=== Chain ID:", result.chainId);

        // 1. Deploy or use existing ZEN token
        result.zenToken = deployZENToken();

        // 2. Deploy ZK Verifier (mock for now)
        result.zkVerifier = deployZKVerifier();

        // 3. Deploy Singularity Integration (mock for now)
        result.singularityIntegration = deploySingularityIntegration();

        // 4. Deploy Trading Factory
        result.tradingFactory = deployTradingFactory(
            result.zkVerifier,
            result.singularityIntegration
        );

        // 5. Deploy test token for trading pairs
        result.testToken = deployTestToken();

        return result;
    }

    /**
     * @dev Deploy ZEN token contract
     */
    function deployZENToken() internal returns (address zenToken) {
        // Check if we're on a network with existing ZEN
        if (block.chainid == HorizenConfig.BASE_MAINNET_CHAIN_ID) {
            // Use existing ZEN on mainnet
            zenToken = HorizenConfig.ZEN_MAINNET;
            console2.log("Using existing ZEN token on mainnet:", zenToken);
        } else if (
            block.chainid == HorizenConfig.BASE_SEPOLIA_CHAIN_ID ||
            block.chainid == HorizenConfig.HORIZEN_TESTNET_CHAIN_ID
        ) {
            // Deploy new ZEN for testing (or use existing testnet ZEN)
            ZEN zen = new ZEN(
                "Horizen",
                "ZEN",
                1_000_000 * 10**18, // 1M ZEN initial supply for testing
                msg.sender
            );
            zenToken = address(zen);
            console2.log("Deployed ZEN token:", zenToken);
        } else {
            revert("Unsupported network for ZEN deployment");
        }

        return zenToken;
    }

    /**
     * @dev Deploy ZK Verifier (mock implementation)
     */
    function deployZKVerifier() internal returns (address zkVerifier) {
        MockZKVerifier verifier = new MockZKVerifier();
        zkVerifier = address(verifier);
        console2.log("Deployed ZK Verifier:", zkVerifier);
        return zkVerifier;
    }

    /**
     * @dev Deploy Singularity Integration (placeholder)
     */
    function deploySingularityIntegration() internal returns (address singularityIntegration) {
        // For now, deploy a mock contract
        // In production, this would integrate with actual Singularity
        MockSingularityIntegration mock = new MockSingularityIntegration();
        singularityIntegration = address(mock);
        console2.log("Deployed Singularity Integration:", singularityIntegration);
        return singularityIntegration;
    }

    /**
     * @dev Deploy Trading Factory
     */
    function deployTradingFactory(
        address zkVerifier,
        address singularityIntegration
    ) internal returns (address factory) {
        HorizenTradingFactory tradingFactory = new HorizenTradingFactory(
            zkVerifier,
            singularityIntegration,
            msg.sender // Fee recipient
        );
        factory = address(tradingFactory);
        console2.log("Deployed Trading Factory:", factory);
        return factory;
    }

    /**
     * @dev Deploy test token for trading pairs
     */
    function deployTestToken() internal returns (address testToken) {
        TestERC20 token = new TestERC20(
            "Base Token",
            "BASE",
            18,
            1_000_000 * 10**18 // 1M tokens
        );
        testToken = address(token);
        console2.log("Deployed Test Token:", testToken);
        return testToken;
    }

    /**
     * @dev Log deployment results
     */
    function logDeploymentResults(DeploymentResult memory result) internal pure {
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("Network:", result.networkName);
        console2.log("Chain ID:", result.chainId);
        console2.log("\nContract Addresses:");
        console2.log("ZEN Token:", result.zenToken);
        console2.log("ZK Verifier:", result.zkVerifier);
        console2.log("Singularity Integration:", result.singularityIntegration);
        console2.log("Trading Factory:", result.tradingFactory);
        console2.log("Test Token:", result.testToken);
    }

    /**
     * @dev Generate deployment configuration file
     */
    function generateDeploymentFile(DeploymentResult memory result) internal {
        string memory json = string.concat(
            '{\n',
            '  "network": "', result.networkName, '",\n',
            '  "chainId": ', vm.toString(result.chainId), ',\n',
            '  "contracts": {\n',
            '    "zenToken": "', vm.toString(result.zenToken), '",\n',
            '    "zkVerifier": "', vm.toString(result.zkVerifier), '",\n',
            '    "singularityIntegration": "', vm.toString(result.singularityIntegration), '",\n',
            '    "tradingFactory": "', vm.toString(result.tradingFactory), '",\n',
            '    "testToken": "', vm.toString(result.testToken), '"\n',
            '  },\n',
            '  "deployedAt": ', vm.toString(block.timestamp), '\n',
            '}'
        );

        // Note: In actual deployment, you'd write this to a file
        console2.log("\n=== DEPLOYMENT CONFIG ===");
        console2.log(json);
    }
}

/**
 * @title MockSingularityIntegration
 * @dev Mock implementation of Singularity integration for testing
 */
contract MockSingularityIntegration {
    mapping(address => bool) public privacyProfiles;
    mapping(address => uint8) public privacyLevels;
    mapping(address => bool) public stealthMode;

    function createPrivacyProfile(bytes32, uint8 privacyLevel) external returns (bool) {
        privacyProfiles[msg.sender] = true;
        privacyLevels[msg.sender] = privacyLevel;
        return true;
    }

    function enableStealthMode(bytes32) external returns (bool) {
        stealthMode[msg.sender] = true;
        return true;
    }

    function disableStealthMode() external returns (bool) {
        stealthMode[msg.sender] = false;
        return true;
    }

    function executeStealthTransaction(
        address,
        uint256,
        bytes calldata
    ) external returns (bytes32) {
        return keccak256(abi.encodePacked(msg.sender, block.timestamp));
    }

    function updatePrivacyLevel(uint8 newLevel) external returns (bool) {
        privacyLevels[msg.sender] = newLevel;
        return true;
    }

    function isStealthModeEnabled(address user) external view returns (bool) {
        return stealthMode[user];
    }
}