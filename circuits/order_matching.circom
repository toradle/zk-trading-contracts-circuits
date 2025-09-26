pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template OrderMatching() {
    // Private inputs
    signal input buyAmount;
    signal input buyPrice;
    signal input buySecret;
    signal input sellAmount;
    signal input sellPrice;
    signal input sellSecret;
    signal input matchSalt;

    // Public inputs
    signal input buyCommitment;
    signal input sellCommitment;
    signal input timestamp;

    // Outputs
    signal output matchHash;
    signal output validMatch;
    signal output executionAmount;
    signal output executionPrice;

    // Components
    component buyPoseidon = Poseidon(4);
    component sellPoseidon = Poseidon(4);
    component matchPoseidon = Poseidon(3);
    component priceMatch = GreaterEqThan(64);
    component amountCheck = LessEqThan(64);

    // Verify buy order commitment
    buyPoseidon.inputs[0] <== buyAmount;
    buyPoseidon.inputs[1] <== buyPrice;
    buyPoseidon.inputs[2] <== buySecret;
    buyPoseidon.inputs[3] <== 1; // isBuyOrder = true

    // Verify sell order commitment
    sellPoseidon.inputs[0] <== sellAmount;
    sellPoseidon.inputs[1] <== sellPrice;
    sellPoseidon.inputs[2] <== sellSecret;
    sellPoseidon.inputs[3] <== 0; // isBuyOrder = false

    // Verify commitments match
    buyCommitment === buyPoseidon.out;
    sellCommitment === sellPoseidon.out;

    // Verify price matching (buy price >= sell price)
    priceMatch.in[0] <== buyPrice;
    priceMatch.in[1] <== sellPrice;

    // Verify amount constraints
    amountCheck.in[0] <== sellAmount;
    amountCheck.in[1] <== buyAmount;

    // Generate match hash
    matchPoseidon.inputs[0] <== buyCommitment;
    matchPoseidon.inputs[1] <== sellCommitment;
    matchPoseidon.inputs[2] <== matchSalt;

    matchHash <== matchPoseidon.out;
    validMatch <== priceMatch.out * amountCheck.out;
    executionAmount <== sellAmount; // Execute at sell amount
    executionPrice <== sellPrice;  // Execute at sell price
}

component main = OrderMatching();