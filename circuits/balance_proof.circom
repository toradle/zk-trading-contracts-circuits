pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/smt/smtverifier.circom";

template BalanceProof(levels) {
    // Private inputs
    signal input balance;
    signal input secret;
    signal input siblings[levels];
    signal input oldKey;
    signal input oldValue;
    signal input isOld0;
    signal input key;
    signal input value;

    // Public inputs
    signal input root;
    signal input requiredAmount;
    signal input nullifierHash;

    // Output
    signal output validBalance;

    // Components
    component balanceCheck = GreaterEqThan(64);
    component poseidon = Poseidon(2);
    component smtVerifier = SMTVerifier(levels);

    // Check sufficient balance
    balanceCheck.in[0] <== balance;
    balanceCheck.in[1] <== requiredAmount;

    // Generate leaf hash
    poseidon.inputs[0] <== balance;
    poseidon.inputs[1] <== secret;

    // Verify SMT proof
    smtVerifier.enabled <== 1;
    smtVerifier.fnc <== 0; // 0 for inclusion proof
    smtVerifier.root <== root;
    for (var i = 0; i < levels; i++) {
        smtVerifier.siblings[i] <== siblings[i];
    }
    smtVerifier.oldKey <== oldKey;
    smtVerifier.oldValue <== oldValue;
    smtVerifier.isOld0 <== isOld0;
    smtVerifier.key <== key;
    smtVerifier.value <== poseidon.out;

    // Generate nullifier
    component nullifierPoseidon = Poseidon(2);
    nullifierPoseidon.inputs[0] <== secret;
    nullifierPoseidon.inputs[1] <== 12345; // Nullifier salt
    nullifierHash === nullifierPoseidon.out;

    validBalance <== balanceCheck.out * smtVerifier.root;
}

component main = BalanceProof(20);