async function exampleUsage() {
    // Initialize client
    const tradingClient = new ZKTradingClient(web3, {
        tradingPool: "0x...",
        orderbook: "0x...",
        factory: "0x..."
    });
    
    await tradingClient.init({
        wasm: "./circuits/trade_commitment.wasm",
        zkey: "./circuits/trade_commitment_final.zkey",
        verificationKey: require("./circuits/verification_key.json")
    });
    
    // Create account
    const userAddress = "0x...";
    const account = await tradingClient.createAccount(userAddress);
    console.log("Created account:", account);
    
    // Deposit tokens
    await tradingClient.deposit('base', '1000000000000000000', userAddress); // 1 ZEN
    
    // Create private buy order
    const buyOrder = await tradingClient.createPrivateOrder({
        amount: '1000000000000000000', // 1 ZEN
        price: '2000000000000000000',  // 2 USDC
        isBuyOrder: true
    }, userAddress);
    
    console.log("Buy order created:", buyOrder);
    
    // Execute the trade after commitment phase
    setTimeout(async () => {
        const executeTx = await tradingClient.executePrivateTrade({
            commitment: buyOrder.commitment,
            proof: buyOrder.proof,
            nullifierHash: buyOrder.nullifierHash,
            amount: '1000000000000000000',
            price: '2000000000000000000',
            isBuyOrder: true
        }, userAddress);
        
        console.log("Trade executed:", executeTx);
    }, 3600000); // Wait 1 hour for commitment phase
}