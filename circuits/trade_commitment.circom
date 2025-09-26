pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template TradeCommitment() {
    // Private inputs
    signal input amount;
    signal input price;
    signal input salt;
    signal input traderSecret;
    signal input isBuyOrder;

    // Public inputs
    signal input nullifierHash;
    signal input merkleRoot;
    signal input timestamp;

    // Output
    signal output commitment;
    signal output validTrade;

    // Components
    component poseidon = Poseidon(5);
    component amountCheck = GreaterThan(64);
    component priceCheck = GreaterThan(64);

    // Validate minimum amounts
    amountCheck.in[0] <== amount;
    amountCheck.in[1] <== 1000000; // Minimum 1 token

    priceCheck.in[0] <== price;
    priceCheck.in[1] <== 1; // Minimum price

    // Generate commitment
    poseidon.inputs[0] <== amount;
    poseidon.inputs[1] <== price;
    poseidon.inputs[2] <== salt;
    poseidon.inputs[3] <== traderSecret;
    poseidon.inputs[4] <== isBuyOrder;

    commitment <== poseidon.out;
    validTrade <== amountCheck.out * priceCheck.out;
}

component main = TradeCommitment();