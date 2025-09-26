// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ZKTradingPool.sol";
import "./ZKOrderbook.sol";

/**
 * @title ZKTradingFactory
 * @dev Factory contract for deploying ZK trading pools and orderbooks
 */
contract ZKTradingFactory is Ownable, ReentrancyGuard {
    struct PoolInfo {
        address poolAddress;
        address orderbookAddress;
        address baseToken;
        address quoteToken;
        address creator;
        uint256 createdAt;
        bool isActive;
        string name;
    }

    // State variables
    mapping(bytes32 => PoolInfo) public pools;
    mapping(address => bytes32[]) public userPools;
    mapping(address => mapping(address => bytes32)) public tokenPairPools;
    bytes32[] public allPools;

    address public immutable zkVerifier;
    uint256 public poolCreationFee = 0.01 ether;
    uint256 public protocolFee = 100; // 1%
    address public feeRecipient;

    // Events
    event PoolCreated(
        bytes32 indexed poolId,
        address indexed creator,
        address poolAddress,
        address orderbookAddress,
        address baseToken,
        address quoteToken,
        string name
    );
    event PoolDeactivated(bytes32 indexed poolId, address indexed deactivator);
    event PoolCreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    // Custom errors
    error InsufficientFee();
    error IdenticalTokens();
    error PoolAlreadyExists();
    error PoolNotFound();
    error UnauthorizedDeactivation();
    error FeeTooHigh();

    constructor(address _zkVerifier, address _feeRecipient) Ownable(msg.sender) {
        require(_zkVerifier != address(0), "Invalid verifier");
        zkVerifier = _zkVerifier;
        feeRecipient = _feeRecipient != address(0) ? _feeRecipient : msg.sender;
    }

    /**
     * @dev Create a new trading pool with orderbook
     */
    function createTradingPool(
        address baseToken,
        address quoteToken,
        string calldata poolName
    ) external payable nonReentrant returns (address poolAddress, address orderbookAddress) {
        if (msg.value < poolCreationFee) revert InsufficientFee();
        if (baseToken == quoteToken) revert IdenticalTokens();
        
        bytes32 poolId = _getPoolId(baseToken, quoteToken);
        if (pools[poolId].poolAddress != address(0)) revert PoolAlreadyExists();

        // Deploy trading pool
        ZKTradingPool pool = new ZKTradingPool(
            baseToken,
            quoteToken,
            zkVerifier,
            msg.sender
        );
        poolAddress = address(pool);

        // Deploy orderbook
        ZKOrderbook orderbook = new ZKOrderbook(zkVerifier, poolAddress);
        orderbookAddress = address(orderbook);

        // Store pool info
        pools[poolId] = PoolInfo({
            poolAddress: poolAddress,
            orderbookAddress: orderbookAddress,
            baseToken: baseToken,
            quoteToken: quoteToken,
            creator: msg.sender,
            createdAt: block.timestamp,
            isActive: true,
            name: poolName
        });

        // Update mappings
        userPools[msg.sender].push(poolId);
        tokenPairPools[baseToken][quoteToken] = poolId;
        tokenPairPools[quoteToken][baseToken] = poolId; // Bidirectional mapping
        allPools.push(poolId);

        // Transfer creation fee
        if (msg.value > 0) {
            payable(feeRecipient).transfer(msg.value);
        }

        emit PoolCreated(poolId, msg.sender, poolAddress, orderbookAddress, baseToken, quoteToken, poolName);

        return (poolAddress, orderbookAddress);
    }

    /**
     * @dev Deactivate a pool (only creator or owner)
     */
    function deactivatePool(bytes32 poolId) external {
        PoolInfo storage pool = pools[poolId];
        if (pool.poolAddress == address(0)) revert PoolNotFound();
        if (msg.sender != pool.creator && msg.sender != owner()) {
            revert UnauthorizedDeactivation();
        }

        pool.isActive = false;
        emit PoolDeactivated(poolId, msg.sender);
    }

    /**
     * @dev Get pool ID from token pair
     */
    function getPoolId(address baseToken, address quoteToken) external pure returns (bytes32) {
        return _getPoolId(baseToken, quoteToken);
    }

    /**
     * @dev Get pool info by tokens
     */
    function getPoolByTokens(address token0, address token1) external view returns (PoolInfo memory) {
        bytes32 poolId = tokenPairPools[token0][token1];
        return pools[poolId];
    }

    /**
     * @dev Get all pools created by a user
     */
    function getUserPools(address user) external view returns (bytes32[] memory) {
        return userPools[user];
    }

    /**
     * @dev Get all active pools
     */
    function getActivePools() external view returns (bytes32[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (pools[allPools[i]].isActive) {
                activeCount++;
            }
        }

        bytes32[] memory activePools = new bytes32[](activeCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (pools[allPools[i]].isActive) {
                activePools[currentIndex] = allPools[i];
                currentIndex++;
            }
        }

        return activePools;
    }

    /**
     * @dev Get all pools
     */
    function getAllPools() external view returns (bytes32[] memory) {
        return allPools;
    }

    /**
     * @dev Get total number of pools
     */
    function getTotalPools() external view returns (uint256) {
        return allPools.length;
    }

    /**
     * @dev Internal function to generate pool ID
     */
    function _getPoolId(address baseToken, address quoteToken) internal pure returns (bytes32) {
        // Ensure consistent ordering for bidirectional lookup
        (address token0, address token1) = baseToken < quoteToken ? 
            (baseToken, quoteToken) : (quoteToken, baseToken);
        return keccak256(abi.encodePacked(token0, token1));
    }

    /**
     * @dev Set pool creation fee (only owner)
     */
    function setPoolCreationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = poolCreationFee;
        poolCreationFee = newFee;
        emit PoolCreationFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Set protocol fee (only owner)
     */
    function setProtocolFee(uint256 newFee) external onlyOwner {
        if (newFee > 1000) revert FeeTooHigh(); // Max 10%
        uint256 oldFee = protocolFee;
        protocolFee = newFee;
        emit ProtocolFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Set fee recipient (only owner)
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Withdraw accumulated fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(feeRecipient).transfer(balance);
        }
    }

    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
        }
    }

    /**
     * @dev Receive Ether
     */
    receive() external payable {}
}