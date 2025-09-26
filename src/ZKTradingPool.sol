// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IZKVerifier.sol";
import "./libraries/ZKTypes.sol";
import "./libraries/Poseidon.sol";

/**
 * @title ZKTradingPool
 * @dev Zero-Knowledge enabled trading pool with privacy-preserving features
 */
contract ZKTradingPool is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Poseidon for uint256;

    // Constants
    uint256 public constant COMMITMENT_PHASE_DURATION = 1 hours;
    uint256 public constant MIN_TRADE_AMOUNT = 1e6;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE = 1000; // 10%

    // Immutable state
    IERC20 public immutable baseToken;
    IERC20 public immutable quoteToken;
    IZKVerifier public immutable zkVerifier;

    // State variables
    mapping(bytes32 => ZKTypes.TradeCommitment) public commitments;
    mapping(bytes32 => bool) public nullifierHashes;
    mapping(bytes32 => ZKTypes.PrivateOrder) public privateOrders;
    mapping(address => uint256) public balances;
    mapping(address => uint256) private nonces;

    bytes32[] public activeOrderHashes;
    bytes32 public merkleRoot;
    uint256 public tradingFee = 30; // 0.3%

    // Events
    event CommitmentMade(bytes32 indexed commitment, address indexed user, uint256 timestamp);
    event TradeExecuted(
        bytes32 indexed commitment,
        address indexed trader,
        uint256 amount,
        uint256 price,
        bool isBuyOrder
    );
    event PrivateOrderCreated(bytes32 indexed orderHash, address indexed trader, bool isBuyOrder);
    event PrivateOrderFilled(bytes32 indexed orderHash, uint256 amount, uint256 price);
    event BalanceDeposited(address indexed user, address indexed token, uint256 amount);
    event BalanceWithdrawn(address indexed user, address indexed token, uint256 amount);
    event MerkleRootUpdated(bytes32 newRoot);
    event TradingFeeUpdated(uint256 oldFee, uint256 newFee);

    // Custom errors
    error InvalidProof();
    error CommitmentAlreadyExists();
    error CommitmentNotFound();
    error CommitmentNotReady();
    error NullifierAlreadyUsed();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidToken();
    error OrderNotFound();
    error OrderAlreadyFilled();
    error FeeTooHigh();
    error InvalidFeeAmount();

    /**
     * @dev Constructor
     * @param _baseToken Base token address (e.g., ZEN)
     * @param _quoteToken Quote token address (e.g., USDC)
     * @param _zkVerifier ZK verifier contract address
     * @param _owner Contract owner address
     */
    constructor(
        address _baseToken,
        address _quoteToken,
        address _zkVerifier,
        address _owner
    ) Ownable(_owner) {
        require(_baseToken != address(0), "Invalid base token");
        require(_quoteToken != address(0), "Invalid quote token");
        require(_zkVerifier != address(0), "Invalid verifier");
        require(_baseToken != _quoteToken, "Tokens must be different");

        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
        zkVerifier = IZKVerifier(_zkVerifier);
    }

    /**
     * @dev Deposit tokens to the trading pool
     * @param token Token address to deposit
     * @param amount Amount to deposit
     */
    function deposit(address token, uint256 amount) external nonReentrant whenNotPaused {
        if (token != address(baseToken) && token != address(quoteToken)) {
            revert InvalidToken();
        }
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;

        emit BalanceDeposited(msg.sender, token, amount);
    }

    /**
     * @dev Withdraw tokens from the trading pool
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external nonReentrant {
        if (token != address(baseToken) && token != address(quoteToken)) {
            revert InvalidToken();
        }
        if (balances[msg.sender] < amount) revert InsufficientBalance();

        balances[msg.sender] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit BalanceWithdrawn(msg.sender, token, amount);
    }

    /**
     * @dev Create a commitment for a private trade
     * @param commitment The commitment hash
     */
    function makeCommitment(bytes32 commitment) external nonReentrant whenNotPaused {
        if (commitments[commitment].timestamp != 0) revert CommitmentAlreadyExists();

        commitments[commitment] = ZKTypes.TradeCommitment({
            commitment: commitment,
            timestamp: block.timestamp,
            executed: false,
            nullifierHash: bytes32(0),
            trader: msg.sender
        });

        emit CommitmentMade(commitment, msg.sender, block.timestamp);
    }

    /**
     * @dev Execute a private trade with ZK proof
     */
    function executePrivateTrade(
        bytes32 commitment,
        ZKTypes.Proof memory proof,
        bytes32 nullifierHash,
        uint256 amount,
        uint256 price,
        bool isBuyOrder
    ) external nonReentrant whenNotPaused {
        ZKTypes.TradeCommitment storage tradeCommitment = commitments[commitment];

        if (tradeCommitment.timestamp == 0) revert CommitmentNotFound();
        if (tradeCommitment.executed) revert CommitmentAlreadyExists();
        if (block.timestamp < tradeCommitment.timestamp + COMMITMENT_PHASE_DURATION) {
            revert CommitmentNotReady();
        }
        if (nullifierHashes[nullifierHash]) revert NullifierAlreadyUsed();

        // Verify ZK proof
        bool proofValid = zkVerifier.verifyProof(proof.a, proof.b, proof.c, [uint256(commitment)]);
        if (!proofValid) revert InvalidProof();

        // Mark nullifier as used
        nullifierHashes[nullifierHash] = true;
        tradeCommitment.executed = true;
        tradeCommitment.nullifierHash = nullifierHash;

        // Execute the trade
        _executeTrade(tradeCommitment.trader, amount, price, isBuyOrder);

        emit TradeExecuted(commitment, tradeCommitment.trader, amount, price, isBuyOrder);
    }

    /**
     * @dev Internal function for executing private trade (used by batch processing)
     */
    function _executePrivateTradeInternal(
        bytes32 commitment,
        ZKTypes.Proof memory proof,
        bytes32 nullifierHash,
        uint256 amount,
        uint256 price,
        bool isBuyOrder
    ) internal {
        ZKTypes.TradeCommitment storage tradeCommitment = commitments[commitment];

        if (tradeCommitment.timestamp == 0) revert CommitmentNotFound();
        if (tradeCommitment.executed) revert CommitmentAlreadyExists();
        if (block.timestamp < tradeCommitment.timestamp + COMMITMENT_PHASE_DURATION) {
            revert CommitmentNotReady();
        }
        if (nullifierHashes[nullifierHash]) revert NullifierAlreadyUsed();

        // Verify ZK proof
        bool proofValid = zkVerifier.verifyProof(proof.a, proof.b, proof.c, [uint256(commitment)]);
        if (!proofValid) revert InvalidProof();

        // Mark nullifier as used
        nullifierHashes[nullifierHash] = true;
        tradeCommitment.executed = true;
        tradeCommitment.nullifierHash = nullifierHash;

        // Execute the trade
        _executeTrade(tradeCommitment.trader, amount, price, isBuyOrder);

        emit TradeExecuted(commitment, tradeCommitment.trader, amount, price, isBuyOrder);
    }

    /**
     * @dev Create a private order using ZK proofs
     */
    function createPrivateOrder(
        ZKTypes.Proof memory proof,
        bytes32 orderHash,
        bytes32 encryptedAmount,
        bytes32 encryptedPrice,
        bool isBuyOrder
    ) external nonReentrant whenNotPaused {
        // Verify ZK proof for order creation
        bool proofValid = zkVerifier.verifyProof(proof.a, proof.b, proof.c, [uint256(orderHash)]);
        if (!proofValid) revert InvalidProof();

        privateOrders[orderHash] = ZKTypes.PrivateOrder({
            orderHash: orderHash,
            encryptedAmount: encryptedAmount,
            encryptedPrice: encryptedPrice,
            trader: msg.sender,
            isBuyOrder: isBuyOrder,
            timestamp: block.timestamp,
            filled: false,
            executedAmount: 0,
            executedPrice: 0
        });

        activeOrderHashes.push(orderHash);

        emit PrivateOrderCreated(orderHash, msg.sender, isBuyOrder);
    }

    /**
     * @dev Fill a private order with ZK proof
     */
    function fillPrivateOrder(
        bytes32 orderHash,
        ZKTypes.Proof memory proof,
        uint256 fillAmount,
        uint256 fillPrice
    ) external nonReentrant whenNotPaused {
        ZKTypes.PrivateOrder storage order = privateOrders[orderHash];

        if (order.orderHash == bytes32(0)) revert OrderNotFound();
        if (order.filled) revert OrderAlreadyFilled();

        // Verify ZK proof for order matching
        bool proofValid = zkVerifier.verifyProof(proof.a, proof.b, proof.c, [uint256(orderHash)]);
        if (!proofValid) revert InvalidProof();

        // Execute trades for both parties
        _executeTrade(order.trader, fillAmount, fillPrice, order.isBuyOrder);
        _executeTrade(msg.sender, fillAmount, fillPrice, !order.isBuyOrder);

        // Update order
        order.filled = true;
        order.executedAmount = fillAmount;
        order.executedPrice = fillPrice;

        emit PrivateOrderFilled(orderHash, fillAmount, fillPrice);
    }

    /**
     * @dev Batch process multiple ZK proofs
     */
    function batchProcessZKProofs(
        bytes32[] calldata commitmentsList,
        ZKTypes.Proof[] calldata proofs,
        bytes32[] calldata nullifierHashesList,
        uint256[] calldata amounts,
        uint256[] calldata prices,
        bool[] calldata isBuyOrders
    ) external nonReentrant whenNotPaused {
        uint256 length = commitmentsList.length;
        require(
            proofs.length == length &&
            nullifierHashesList.length == length &&
            amounts.length == length &&
            prices.length == length &&
            isBuyOrders.length == length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < length; i++) {
            _executePrivateTradeInternal(
                commitmentsList[i],
                proofs[i],
                nullifierHashesList[i],
                amounts[i],
                prices[i],
                isBuyOrders[i]
            );
        }
    }

    /**
     * @dev Internal function to execute trade logic
     */
    function _executeTrade(address trader, uint256 amount, uint256 price, bool isBuyOrder) internal {
        if (amount < MIN_TRADE_AMOUNT) revert InvalidAmount();

        uint256 quoteAmount = (amount * price) / 1e18;
        uint256 fee = (quoteAmount * tradingFee) / FEE_DENOMINATOR;
        uint256 netQuoteAmount = quoteAmount - fee;

        if (isBuyOrder) {
            // User is buying base token with quote token
            if (balances[trader] < quoteAmount) revert InsufficientBalance();

            balances[trader] -= quoteAmount;
            baseToken.safeTransfer(trader, amount);
        } else {
            // User is selling base token for quote token
            if (baseToken.balanceOf(trader) < amount) revert InsufficientBalance();

            baseToken.safeTransferFrom(trader, address(this), amount);
            balances[trader] += netQuoteAmount;
        }

        // Collect fees (send to contract owner)
        if (fee > 0) {
            quoteToken.safeTransfer(owner(), fee);
        }
    }

    /**
     * @dev Update Merkle root for privacy set
     */
    function updateMerkleRoot(bytes32 newRoot) external onlyOwner {
        merkleRoot = newRoot;
        emit MerkleRootUpdated(newRoot);
    }

    /**
     * @dev Verify membership in privacy set using Merkle proof
     */
    function verifyMembership(bytes32 leaf, bytes32[] calldata merkleProof)
        external
        view
        returns (bool)
    {
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    /**
     * @dev Get user's trading nonce
     */
    function getNonce(address user) external view returns (uint256) {
        return nonces[user];
    }

    /**
     * @dev Increment user's nonce
     */
    function incrementNonce() external {
        nonces[msg.sender]++;
    }

    /**
     * @dev Get active order hashes
     */
    function getActiveOrderHashes() external view returns (bytes32[] memory) {
        return activeOrderHashes;
    }

    /**
     * @dev Get commitment details
     */
    function getCommitment(bytes32 commitment) external view returns (ZKTypes.TradeCommitment memory) {
        return commitments[commitment];
    }

    /**
     * @dev Get private order details
     */
    function getPrivateOrder(bytes32 orderHash) external view returns (ZKTypes.PrivateOrder memory) {
        return privateOrders[orderHash];
    }

    /**
     * @dev Set trading fee (only owner)
     */
    function setTradingFee(uint256 newFee) external onlyOwner {
        if (newFee > MAX_FEE) revert FeeTooHigh();
        uint256 oldFee = tradingFee;
        tradingFee = newFee;
        emit TradingFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdraw (only owner, when paused)
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner whenPaused {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Receive Ether (for gas refunds)
     */
    receive() external payable {}
}
