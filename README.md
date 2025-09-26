# ZK Trading Horizen 🚀

A Zero-Knowledge trading system built for Horizen on Base, providing privacy-preserving orderbooks and decentralized trading with cryptographic proofs.

## 🌟 Overview

This project implements a complete ZK trading infrastructure including:

- **Privacy-preserving orderbooks** with commitment schemes
- **Zero-knowledge proof verification** for trade matching
- **Decentralized trading pools** with liquidity management
- **Sparse Merkle Trees** for balance proofs
- **Factory pattern** for deploying trading pairs

## 📁 Project Structure

```
zk-trading-horizen/
├── src/                          # Solidity smart contracts
│   ├── interfaces/
│   │   └── IZKVerifier.sol       # ZK verifier interface
│   ├── libraries/
│   │   ├── ZKTypes.sol           # Common data structures
│   │   └── Poseidon.sol          # Hash function library
│   ├── mocks/
│   │   ├── MockZKVerifier.sol    # Mock verifier for testing
│   │   └── TestERC20.sol         # Test token contract
│   ├── ZKOrderbook.sol           # Privacy-preserving orderbook
│   ├── ZKTradingPool.sol         # Main trading pool contract
│   ├── ZKTradingFactory.sol      # Factory for deploying pools
│   └── Counter.sol               # Example contract
├── circuits/                     # Zero-knowledge circuits (Circom)
│   ├── trade_commitment.circom   # Trade commitment circuit
│   ├── order_matching.circom     # Order matching circuit
│   ├── balance_proof.circom      # Balance verification circuit
│   ├── ZKTradingUtils.js         # Utility functions for ZK
│   ├── ZKTradingClient.js        # Client-side ZK operations
│   ├── ZKTradingProofGenerator.js# Proof generation utilities
│   └── MerkleTree.js             # Merkle tree implementation
├── script/                       # Deployment scripts
│   └── Deploy.s.sol              # Main deployment script
├── test/                         # Test files
│   ├── unit/
│   │   └── ZKTypes.t.sol         # Unit tests for types
│   ├── ZKTradingFactory.t.sol    # Factory tests
│   └── ZKTradingPool.t.sol       # Pool tests
├── lib/                          # Dependencies
│   ├── forge-std/                # Foundry standard library
│   └── openzeppelin-contracts/   # OpenZeppelin contracts
├── foundry.toml                  # Foundry configuration
├── remappings.txt                # Import path mappings
├── package.json                  # Node.js dependencies
└── README.md                     # This file
```

## 🔧 Setup & Installation

### Prerequisites

- **Rust & Foundry**: Install from [getfoundry.sh](https://getfoundry.sh)
- **Node.js**: v16+ for circuit compilation
- **Circom**: Zero-knowledge circuit compiler

```bash
# Install Circom (if not already installed)
git clone https://github.com/iden3/circom.git
cd circom
cargo build --release
cargo install --path circom
```

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd zk-trading-horizen
   ```

2. **Install dependencies**
   ```bash
   # Install Foundry dependencies
   forge install

   # Install Node.js dependencies for circuits
   npm install
   ```

3. **Build contracts**
   ```bash
   forge build
   ```

4. **Compile circuits**
   ```bash
   cd circuits

   # Compile all circuits
   circom trade_commitment.circom --r1cs --wasm --sym
   circom order_matching.circom --r1cs --wasm --sym
   circom balance_proof.circom --r1cs --wasm --sym
   ```

## 🏗️ Architecture

### Smart Contracts

#### ZKTradingFactory.sol
- **Purpose**: Factory for deploying trading pools and orderbooks
- **Key Functions**:
  - `createTradingPool()`: Deploy new trading pair
  - `getPoolByTokens()`: Find existing pools
  - `getActivePools()`: List all active pools

#### ZKTradingPool.sol
- **Purpose**: Main trading pool with privacy features
- **Key Functions**:
  - `deposit()`/`withdraw()`: Manage liquidity
  - `makeCommitment()`: Create trade commitment
  - `executePrivateTrade()`: Execute with ZK proof
  - `createPrivateOrder()`: Submit private orders

#### ZKOrderbook.sol
- **Purpose**: Privacy-preserving orderbook
- **Key Functions**:
  - `commitOrder()`: Submit encrypted order
  - `matchOrders()`: Match orders with ZK proofs
  - `executeMatch()`: Execute matched trades

### Zero-Knowledge Circuits

#### trade_commitment.circom
- **Purpose**: Generate commitments for private trades
- **Inputs**: amount, price, salt, traderSecret, isBuyOrder
- **Outputs**: commitment hash, validation flag
- **Constraints**: 452 non-linear constraints

#### order_matching.circom
- **Purpose**: Verify order compatibility and matching
- **Inputs**: buy/sell order details, commitments
- **Outputs**: match hash, execution parameters
- **Constraints**: 980 non-linear constraints

#### balance_proof.circom
- **Purpose**: Prove sufficient balance without revealing amount
- **Inputs**: balance, secret, Merkle proof
- **Outputs**: validity proof
- **Constraints**: 6,804 non-linear constraints (uses SMT)

## 🚀 Usage

### Development

```bash
# Run tests
forge test

# Run tests with gas reporting
npm run test:gas

# Run coverage analysis
npm run test:coverage

# Format code
npm run format

# Lint contracts
npm run lint
```

### Deployment

```bash
# Deploy to local network
npm run deploy:local

# Deploy to Base mainnet
npm run deploy:base

# Deploy to Base Sepolia testnet
npm run deploy:sepolia
```

### Circuit Operations

```bash
# Compile circuits
npm run circuits:compile

# Setup trusted setup (for production)
npm run circuits:setup
```

## 🔐 Zero-Knowledge Workflow

### 1. Trade Commitment
```javascript
// Generate commitment for private trade
const commitment = await utils.createTradeCommitment(
  amount,
  price,
  salt,
  traderSecret,
  isBuyOrder
);
```

### 2. Order Submission
```javascript
// Submit private order to orderbook
await orderbook.commitOrder(orderId, commitment, isBuyOrder);
```

### 3. Order Matching
```javascript
// Generate proof for order matching
const proof = await generateMatchingProof(buyOrder, sellOrder);
await orderbook.matchOrders(buyOrderId, sellOrderId, matchCommitment, proof);
```

### 4. Trade Execution
```javascript
// Execute matched trade with proof
const executionProof = await generateExecutionProof(matchId);
await orderbook.executeMatch(matchId, executionProof, amount, price);
```

## 🧪 Testing

### Smart Contract Tests
```bash
# Run all tests
forge test -vvv

# Run specific test
forge test --match-contract ZKTradingPoolTest

# Run with gas reporting
forge test --gas-report
```

### Circuit Tests
```bash
# Test circuit compilation
cd circuits
circom trade_commitment.circom --r1cs --wasm --sym

# Verify circuit constraints
snarkjs info -c trade_commitment.r1cs
```

## 📊 Circuit Statistics

| Circuit | Constraints | Public Inputs | Private Inputs | Output Size |
|---------|-------------|---------------|----------------|-------------|
| Trade Commitment | 452 | 3 | 5 | 2 |
| Order Matching | 980 | 3 | 7 | 4 |
| Balance Proof | 6,804 | 3 | 27 | 1 |

## 🔧 Configuration

### Foundry Configuration (foundry.toml)
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
via_ir = true  # Required for complex contracts
```

### Import Remappings (remappings.txt)
```
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
forge-std/=lib/forge-std/src/
@forge-std/=lib/forge-std/src/
```

## 🛡️ Security Features

- **Zero-Knowledge Proofs**: Trade amounts and prices remain private
- **Commitment Schemes**: Prevent front-running and MEV attacks
- **Sparse Merkle Trees**: Efficient balance verification
- **Reentrancy Protection**: All external calls protected
- **Access Control**: Owner-based permissions for critical functions
- **Pausable Contracts**: Emergency stop functionality

## 📈 Gas Optimization

- **IR-based Compilation**: Reduces gas costs for complex functions
- **Batch Operations**: Process multiple proofs in single transaction
- **Efficient Data Structures**: Optimized storage layouts
- **Circuit Optimization**: Minimized constraint counts

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🔗 Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
- [Circom Documentation](https://docs.circom.io/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Base Network](https://base.org/)
- [Horizen](https://www.horizen.io/)

## ⚠️ Disclaimer

This is experimental software. Do not use in production without proper security audits. The zero-knowledge circuits and smart contracts have not been formally verified.

---

Built with ❤️ for the Horizen ecosystem on Base