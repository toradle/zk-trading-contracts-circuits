// =============================================================================
// TRADING CLIENT IMPLEMENTATION
// =============================================================================

class ZKTradingClient {
    constructor(web3Provider, contractAddresses) {
        this.web3 = web3Provider;
        this.contracts = {
            tradingPool: new this.web3.eth.Contract(TRADING_POOL_ABI, contractAddresses.tradingPool),
            orderbook: new this.web3.eth.Contract(ORDERBOOK_ABI, contractAddresses.orderbook),
            factory: new this.web3.eth.Contract(FACTORY_ABI, contractAddresses.factory)
        };
        
        this.utils = new ZKTradingUtils();
        this.proofGenerator = null;
        this.userSecrets = new Map();
    }
    
    async init(circuitFiles) {
        await this.utils.init();
        
        this.proofGenerator = new ZKTradingProofGenerator(
            circuitFiles.wasm,
            circuitFiles.zkey,
            circuitFiles.verificationKey
        );
    }
    
    /**
     * Create a private trading account
     */
    async createAccount(userAddress) {
        const secret = this.utils.generateTraderSecret();
        this.userSecrets.set(userAddress, secret);
        
        return {
            address: userAddress,
            secret: secret.toString()
        };
    }
    
    /**
     * Deposit tokens to trading pool
     */
    async deposit(token, amount, userAddress) {
        const contract = token === 'base' ? 
            this.contracts.tradingPool.methods.deposit(this.contracts.baseToken, amount) :
            this.contracts.tradingPool.methods.deposit(this.contracts.quoteToken, amount);
            
        return await contract.send({ from: userAddress });
    }
    
    /**
     * Create a private trade order
     */
    async createPrivateOrder(orderData, userAddress) {
        const { amount, price, isBuyOrder } = orderData;
        const secret = this.userSecrets.get(userAddress);
        
        if (!secret) {
            throw new Error("User secret not found. Create account first.");
        }
        
        // Generate commitment
        const salt = this.utils.generateSalt();
        const commitment = await this.utils.createTradeCommitment(
            amount, price, salt, secret, isBuyOrder
        );
        
        // Step 1: Make commitment
        const commitTx = await this.contracts.tradingPool.methods
            .makeCommitment(commitment.toString())
            .send({ from: userAddress });
        
        // Wait for commitment phase
        console.log("Commitment made, waiting for commitment phase...");
        
        // Step 2: Generate ZK proof
        const nullifierHash = await this.utils.createNullifierHash(secret);
        const merkleRoot = await this.contracts.tradingPool.methods.merkleRoot().call();
        
        const proofData = await this.proofGenerator.generateTradeCommitmentProof({
            amount,
            price,
            salt,
            traderSecret: secret,
            isBuyOrder,
            nullifierHash,
            merkleRoot,
            timestamp: Date.now()
        });
        
        return {
            commitment: commitment.toString(),
            proof: proofData.proof,
            nullifierHash: nullifierHash.toString(),
            salt,
            commitTx
        };
    }
    
    /**
     * Execute private trade
     */
    async executePrivateTrade(tradeData, userAddress) {
        const { commitment, proof, nullifierHash, amount, price, isBuyOrder } = tradeData;
        
        const zkProof = {
            a: proof.a,
            b: proof.b,
            c: proof.c,
            publicSignals: proof.publicSignals
        };
        
        return await this.contracts.tradingPool.methods
            .executePrivateTrade(
                commitment,
                zkProof,
                nullifierHash,
                amount,
                price,
                isBuyOrder
            )
            .send({ from: userAddress });
    }
    
    /**
     * Match two orders
     */
    async matchOrders(buyOrderData, sellOrderData, userAddress) {
        // Generate matching proof
        const matchSalt = this.utils.generateSalt();
        const proofData = await this.proofGenerator.generateOrderMatchingProof({
            buyAmount: buyOrderData.amount,
            buyPrice: buyOrderData.price,
            buySecret: buyOrderData.secret,
            sellAmount: sellOrderData.amount,
            sellPrice: sellOrderData.price,
            sellSecret: sellOrderData.secret,
            matchSalt,
            buyCommitment: buyOrderData.commitment,
            sellCommitment: sellOrderData.commitment,
            timestamp: Date.now()
        });
        
        const zkProof = {
            a: proofData.proof.a,
            b: proofData.proof.b,
            c: proofData.proof.c,
            publicSignals: proofData.publicSignals
        };
        
        return await this.contracts.orderbook.methods
            .matchOrders(
                buyOrderData.id,
                sellOrderData.id,
                proofData.publicSignals[0], // matchHash
                zkProof
            )
            .send({ from: userAddress });
    }
    
    /**
     * Get user's trading balance
     */
    async getBalance(userAddress) {
        return await this.contracts.tradingPool.methods.balances(userAddress).call();
    }
    
    /**
     * Get active orders
     */
    async getActiveOrders() {
        const buyOrders = await this.contracts.orderbook.methods.getActiveOrders(true).call();
        const sellOrders = await this.contracts.orderbook.methods.getActiveOrders(false).call();
        
        return { buyOrders, sellOrders };
    }
}