class ZKTradingProofGenerator {
    constructor(circuitWasm, circuitZkey, verificationKey) {
        this.circuitWasm = circuitWasm;
        this.circuitZkey = circuitZkey;
        this.verificationKey = verificationKey;
    }
    
    /**
     * Generate a trade commitment proof
     */
    async generateTradeCommitmentProof(tradeData) {
        const { amount, price, salt, traderSecret, isBuyOrder, nullifierHash, merkleRoot, timestamp } = tradeData;
        
        const input = {
            amount: amount.toString(),
            price: price.toString(),
            salt: salt.toString(),
            traderSecret: traderSecret.toString(),
            isBuyOrder: isBuyOrder ? "1" : "0",
            nullifierHash: nullifierHash.toString(),
            merkleRoot: merkleRoot.toString(),
            timestamp: timestamp.toString()
        };
        
        try {
            // Generate witness
            const { witness } = await snarkjs.wtns.calculate(input, this.circuitWasm);
            
            // Generate proof
            const { proof, publicSignals } = await snarkjs.groth16.prove(this.circuitZkey, witness);
            
            return {
                proof: this.formatProofForSolidity(proof),
                publicSignals: publicSignals.map(s => s.toString())
            };
        } catch (error) {
            console.error("Error generating trade commitment proof:", error);
            throw error;
        }
    }
    
    /**
     * Generate an order matching proof
     */
    async generateOrderMatchingProof(matchData) {
        const {
            buyAmount, buyPrice, buySecret,
            sellAmount, sellPrice, sellSecret,
            matchSalt, buyCommitment, sellCommitment, timestamp
        } = matchData;
        
        const input = {
            buyAmount: buyAmount.toString(),
            buyPrice: buyPrice.toString(),
            buySecret: buySecret.toString(),
            sellAmount: sellAmount.toString(),
            sellPrice: sellPrice.toString(),
            sellSecret: sellSecret.toString(),
            matchSalt: matchSalt.toString(),
            buyCommitment: buyCommitment.toString(),
            sellCommitment: sellCommitment.toString(),
            timestamp: timestamp.toString()
        };
        
        try {
            const { witness } = await snarkjs.wtns.calculate(input, this.circuitWasm);
            const { proof, publicSignals } = await snarkjs.groth16.prove(this.circuitZkey, witness);
            
            return {
                proof: this.formatProofForSolidity(proof),
                publicSignals: publicSignals.map(s => s.toString())
            };
        } catch (error) {
            console.error("Error generating order matching proof:", error);
            throw error;
        }
    }
    
    /**
     * Generate a balance proof
     */
    async generateBalanceProof(balanceData) {
        const {
            balance, secret, pathElements, pathIndices,
            root, requiredAmount, nullifierHash
        } = balanceData;
        
        const input = {
            balance: balance.toString(),
            secret: secret.toString(),
            pathElements: pathElements.map(e => e.toString()),
            pathIndices: pathIndices.map(i => i.toString()),
            root: root.toString(),
            requiredAmount: requiredAmount.toString(),
            nullifierHash: nullifierHash.toString()
        };
        
        try {
            const { witness } = await snarkjs.wtns.calculate(input, this.circuitWasm);
            const { proof, publicSignals } = await snarkjs.groth16.prove(this.circuitZkey, witness);
            
            return {
                proof: this.formatProofForSolidity(proof),
                publicSignals: publicSignals.map(s => s.toString())
            };
        } catch (error) {
            console.error("Error generating balance proof:", error);
            throw error;
        }
    }
    
    /**
     * Format proof for Solidity contract
     */
    formatProofForSolidity(proof) {
        return {
            a: [proof.pi_a[0], proof.pi_a[1]],
            b: [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]],
            c: [proof.pi_c[0], proof.pi_c[1]]
        };
    }
    
    /**
     * Verify a proof
     */
    async verifyProof(proof, publicSignals) {
        try {
            const result = await snarkjs.groth16.verify(this.verificationKey, publicSignals, proof);
            return result;
        } catch (error) {
            console.error("Error verifying proof:", error);
            return false;
        }
    }
}

// Export modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        ZKTradingProofGenerator,
        ZKTradingUtils,
        MerkleTree,
        ZKTradingClient,
        tradeCommitmentCircuit,
        orderMatchingCircuit,
        balanceProofCircuit
    };
}