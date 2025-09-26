// =============================================================================
// TRADING UTILITIES
// =============================================================================

class ZKTradingUtils {
    constructor() {
        this.poseidon = null;
    }
    
    async init() {
        // Initialize Poseidon hash function
        this.poseidon = await circomlib.poseidon;
    }
    
    /**
     * Generate a random salt
     */
    generateSalt() {
        return BigInt("0x" + crypto.getRandomValues(new Uint8Array(32)).reduce((str, byte) => str + byte.toString(16).padStart(2, '0'), ''));
    }
    
    /**
     * Generate trader secret
     */
    generateTraderSecret() {
        return this.generateSalt();
    }
    
    /**
     * Create trade commitment
     */
    async createTradeCommitment(amount, price, salt, traderSecret, isBuyOrder) {
        const inputs = [
            BigInt(amount),
            BigInt(price),
            BigInt(salt),
            BigInt(traderSecret),
            BigInt(isBuyOrder ? 1 : 0)
        ];
        
        return await this.poseidon(inputs);
    }
    
    /**
     * Create nullifier hash
     */
    async createNullifierHash(secret, salt = 12345n) {
        return await this.poseidon([BigInt(secret), BigInt(salt)]);
    }
    
    /**
     * Create order hash
     */
    async createOrderHash(commitment, timestamp, trader) {
        const traderBigInt = BigInt(trader);
        return await this.poseidon([BigInt(commitment), BigInt(timestamp), traderBigInt]);
    }
    
    /**
     * Generate Merkle tree for privacy set
     */
    generateMerkleTree(leaves) {
        const tree = new MerkleTree(leaves.length);
        for (let i = 0; i < leaves.length; i++) {
            tree.insert(leaves[i]);
        }
        return tree;
    }
}