// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZKVerifier.sol";
import "./libraries/ZKTypes.sol";
import "./ZKTradingPool.sol";

/**
 * @title ZKOrderbook
 * @dev Zero-knowledge orderbook for private trading
 */
contract ZKOrderbook is ReentrancyGuard, Ownable {
    // State variables
    mapping(bytes32 => ZKTypes.PrivateOrder) public orders;
    mapping(bytes32 => ZKTypes.OrderMatch) public matches;
    mapping(bytes32 => bool) public commitmentUsed;

    bytes32[] public buyOrders;
    bytes32[] public sellOrders;

    IZKVerifier public immutable zkVerifier;
    ZKTradingPool public immutable tradingPool;

    // Events
    event OrderCommitted(bytes32 indexed orderId, address indexed trader, bytes32 commitment);
    event OrdersMatched(bytes32 indexed matchId, bytes32 buyOrder, bytes32 sellOrder);
    event MatchExecuted(bytes32 indexed matchId, uint256 amount, uint256 price);

    // Custom errors
    error CommitmentAlreadyUsed();
    error OrderNotActive();
    error InvalidMatchProof();
    error InvalidExecutionProof();
    error MatchAlreadyExecuted();

    constructor(address _zkVerifier, address _tradingPool) Ownable(msg.sender) {
        require(_zkVerifier != address(0), "Invalid verifier");
        require(_tradingPool != address(0), "Invalid trading pool");

        zkVerifier = IZKVerifier(_zkVerifier);
        tradingPool = ZKTradingPool(payable(_tradingPool));
    }

    /**
     * @dev Commit to a new order
     */
    function commitOrder(bytes32 orderId, bytes32 commitment, bool isBuyOrder)
        external
        nonReentrant
    {
        if (commitmentUsed[commitment]) revert CommitmentAlreadyUsed();

        orders[orderId] = ZKTypes.PrivateOrder({
            orderHash: orderId,
            encryptedAmount: commitment, // Simplified for demo
            encryptedPrice: commitment,  // Simplified for demo
            trader: msg.sender,
            isBuyOrder: isBuyOrder,
            timestamp: block.timestamp,
            filled: false,
            executedAmount: 0,
            executedPrice: 0
        });

        commitmentUsed[commitment] = true;

        if (isBuyOrder) {
            buyOrders.push(orderId);
        } else {
            sellOrders.push(orderId);
        }

        emit OrderCommitted(orderId, msg.sender, commitment);
    }

    /**
     * @dev Match two orders privately
     */
    function matchOrders(
        bytes32 buyOrderId,
        bytes32 sellOrderId,
        bytes32 matchCommitment,
        ZKTypes.Proof memory matchProof
    ) external nonReentrant {
        if (!orders[buyOrderId].isBuyOrder || orders[buyOrderId].filled) {
            revert OrderNotActive();
        }
        if (orders[sellOrderId].isBuyOrder || orders[sellOrderId].filled) {
            revert OrderNotActive();
        }

        // Verify ZK proof for order matching
        bool proofValid = zkVerifier.verifyProof(
            matchProof.a,
            matchProof.b,
            matchProof.c,
            [uint256(matchCommitment)]
        );
        if (!proofValid) revert InvalidMatchProof();

        bytes32 matchId = keccak256(abi.encodePacked(buyOrderId, sellOrderId, block.timestamp));

        matches[matchId] = ZKTypes.OrderMatch({
            buyOrderId: buyOrderId,
            sellOrderId: sellOrderId,
            matchCommitment: matchCommitment,
            timestamp: block.timestamp,
            executed: false,
            amount: 0,
            price: 0
        });

        emit OrdersMatched(matchId, buyOrderId, sellOrderId);
    }

    /**
     * @dev Execute a matched trade
     */
    function executeMatch(
        bytes32 matchId,
        ZKTypes.Proof memory executionProof,
        uint256 amount,
        uint256 price
    ) external nonReentrant {
        ZKTypes.OrderMatch storage orderMatch = matches[matchId];
        if (orderMatch.executed) revert MatchAlreadyExecuted();

        // Verify execution proof
        bool proofValid = zkVerifier.verifyProof(
            executionProof.a,
            executionProof.b,
            executionProof.c,
            [uint256(matchId)]
        );
        if (!proofValid) revert InvalidExecutionProof();

        // Mark orders as filled
        orders[orderMatch.buyOrderId].filled = true;
        orders[orderMatch.buyOrderId].executedAmount = amount;
        orders[orderMatch.buyOrderId].executedPrice = price;
        
        orders[orderMatch.sellOrderId].filled = true;
        orders[orderMatch.sellOrderId].executedAmount = amount;
        orders[orderMatch.sellOrderId].executedPrice = price;

        // Update match
        orderMatch.executed = true;
        orderMatch.amount = amount;
        orderMatch.price = price;

        emit MatchExecuted(matchId, amount, price);
    }

    /**
     * @dev Get active orders by type
     */
    function getActiveOrders(bool isBuyOrder) external view returns (bytes32[] memory) {
        if (isBuyOrder) {
            return buyOrders;
        } else {
            return sellOrders;
        }
    }

    /**
     * @dev Get order details
     */
    function getOrder(bytes32 orderId) external view returns (ZKTypes.PrivateOrder memory) {
        return orders[orderId];
    }

    /**
     * @dev Get match details
     */
    function getMatch(bytes32 matchId) external view returns (ZKTypes.OrderMatch memory) {
        return matches[matchId];
    }

    /**
     * @dev Get all orders for a trader
     */
    function getTraderOrders(address trader) external view returns (bytes32[] memory) {
        bytes32[] memory traderOrders = new bytes32[](buyOrders.length + sellOrders.length);
        uint256 count = 0;

        for (uint256 i = 0; i < buyOrders.length; i++) {
            if (orders[buyOrders[i]].trader == trader) {
                traderOrders[count] = buyOrders[i];
                count++;
            }
        }

        for (uint256 i = 0; i < sellOrders.length; i++) {
            if (orders[sellOrders[i]].trader == trader) {
                traderOrders[count] = sellOrders[i];
                count++;
            }
        }

        // Resize array to actual count
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = traderOrders[i];
        }

        return result;
    }
}