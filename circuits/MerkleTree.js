// =============================================================================
// MERKLE TREE IMPLEMENTATION
// =============================================================================

class MerkleTree {
    constructor(depth) {
        this.depth = depth;
        this.size = 2 ** depth;
        this.tree = new Array(2 * this.size);
        this.nextIndex = 0;
        
        // Initialize tree with zeros
        for (let i = 0; i < this.tree.length; i++) {
            this.tree[i] = 0n;
        }
    }
    
    async insert(leaf) {
        if (this.nextIndex >= this.size) {
            throw new Error("Tree is full");
        }
        
        this.tree[this.size + this.nextIndex] = BigInt(leaf);
        await this.updatePath(this.nextIndex);
        this.nextIndex++;
        
        return this.nextIndex - 1;
    }
    
    async updatePath(index) {
        let currentIndex = this.size + index;
        
        while (currentIndex > 1) {
            const siblingIndex = currentIndex % 2 === 0 ? currentIndex + 1 : currentIndex - 1;
            const parentIndex = Math.floor(currentIndex / 2);
            
            const left = this.tree[Math.min(currentIndex, siblingIndex)];
            const right = this.tree[Math.max(currentIndex, siblingIndex)];
            
            // Use Poseidon hash for internal nodes
            this.tree[parentIndex] = await circomlib.poseidon([left, right]);
            currentIndex = parentIndex;
        }
    }
    
    getRoot() {
        return this.tree[1];
    }
    
    getProof(index) {
        if (index >= this.nextIndex) {
            throw new Error("Index out of bounds");
        }
        
        const pathElements = [];
        const pathIndices = [];
        let currentIndex = this.size + index;
        
        while (currentIndex > 1) {
            const siblingIndex = currentIndex % 2 === 0 ? currentIndex + 1 : currentIndex - 1;
            pathElements.push(this.tree[siblingIndex]);
            pathIndices.push(currentIndex % 2);
            currentIndex = Math.floor(currentIndex / 2);
        }
        
        return { pathElements, pathIndices };
    }
    
    async verifyProof(leaf, proof, root) {
        let currentHash = BigInt(leaf);
        
        for (let i = 0; i < proof.pathElements.length; i++) {
            const pathElement = BigInt(proof.pathElements[i]);
            
            if (proof.pathIndices[i] === 0) {
                // Current node is left child
                currentHash = await circomlib.poseidon([currentHash, pathElement]);
            } else {
                // Current node is right child
                currentHash = await circomlib.poseidon([pathElement, currentHash]);
            }
        }
        
        return currentHash === BigInt(root);
    }
}