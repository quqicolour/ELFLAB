const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting AroundMarket deployment and full test...\n");

  // 获取部署者账户
  const [deployer, user1, user2] = await ethers.getSigners();
  console.log(`📝 Deployer address: ${deployer.address}`);
  console.log(`👤 User1 address: ${user1.address}`);
  console.log(`👤 User2 address: ${user2.address}`);

  // 部署参数
  const MARKET_FEE = 600; // 0.3%
  const PERIOD = 7 * 24 * 60 * 60; // 7 days
  const VIRTUAL_LIQUIDITY = ethers.parseEther("1000");
  const COLLATERAL_AMOUNT = 0;
  const QUEST = "Will ETH price reach $5000 by the end of 2024?";

  console.log("\n📦 Step 1: Deploying MockERC20 token...");
  
  // 部署MockERC20
  const MockERC20 = await ethers.getContractFactory("TestToken");
  const token = await MockERC20.deploy("Test Token", "TEST", ethers.parseEther("1000000"));
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log(`✅ MockERC20 deployed to: ${tokenAddress}`);

  // 分配代币给测试用户
  console.log("\n💰 Distributing tokens to test users...");
  await token.transfer(user1.address, ethers.parseEther("10000"));
  await token.transfer(user2.address, ethers.parseEther("10000"));
  console.log(`✅ Transferred 10,000 TEST tokens to user1 and user2`);

  console.log("\n📦 Step 2: Deploying AroundMarket contract...");
  
  // 部署AroundMarket
  const AroundMarket = await ethers.getContractFactory("AroundMarket");
  const market = await AroundMarket.deploy();
  await market.waitForDeployment();
  const marketAddress = await market.getAddress();
  console.log(`✅ AroundMarket deployed to: ${marketAddress}`);

  console.log("\n🎯 Step 3: Testing Market Creation...");
  
  // 授权并创建市场
  await token.approve(marketAddress, COLLATERAL_AMOUNT);
  console.log(`✅ Approved ${ethers.formatEther(COLLATERAL_AMOUNT)} TEST tokens for market creation`);
  
  const create = await market.createMarket(
    MARKET_FEE,
    PERIOD,
    VIRTUAL_LIQUIDITY,
    COLLATERAL_AMOUNT,
    tokenAddress,
    QUEST
  );
  const createTx = await create.wait();
  console.log(`✅ Market created successfully! Market ID: 0`, createTx.hash);
  
  // 验证市场信息
  let marketInfo = await market.marketInfo(0);
  console.log(`📊 Market Info:`);
  console.log(`   - Creator: ${marketInfo.creator}`);
  console.log(`   - Collateral: ${marketInfo.collateral}`);
  console.log(`   - Quest: "${marketInfo.quest}"`);
  console.log(`   - Market Fee: ${marketInfo.marketFee} basis points`);
  console.log(`   - End Time: ${marketInfo.endTime}`);

  let liquidityInfo = await market.liqudityInfo(0);

  console.log("\n🎯 Step 4: Testing Price Functions...");
  
  let yesPrice = await market.getYesPrice(0);
  let noPrice = await market.getNoPrice(0);
  console.log(`📈 YES Price: ${ethers.formatEther(yesPrice)}`);
  console.log(`📉 NO Price: ${ethers.formatEther(noPrice)}`);
  console.log(`✅ Price sum: ${ethers.formatEther(yesPrice + noPrice)} (should be ~1.0)`);

  console.log("\n🎯 Step 5: Testing Liquidity Operations...");
  
  // 用户1添加流动性
  const approveMax = ethers.parseEther("100000000000000000000000");
  const user1LiquidityAmount = ethers.parseEther("500");
  await token.connect(user1).approve(marketAddress, approveMax);
  console.log(`✅ User1 approved ${ethers.formatEther(user1LiquidityAmount)} TEST tokens`);
  
  const addLiqTx = await market.connect(user1).addLiquidity(user1LiquidityAmount, 0);
  await addLiqTx.wait();
  console.log(`✅ User1 added ${ethers.formatEther(user1LiquidityAmount)} liquidity`);

  const addLiq2Tx = await market.connect(user1).addLiquidity(user1LiquidityAmount, 0);
  await addLiq2Tx.wait();
  console.log(`✅ User1 added ${ethers.formatEther(user1LiquidityAmount)} liquidity`);

  // 检查用户仓位
  const user1Position = await market.userPosition(user1.address, 0);
  console.log(`📊 User1 Position after adding liquidity:`);
  console.log(`   - User1 LP: ${ethers.formatEther(user1Position.lp)}`);
  console.log(`   - User1 YES Balance: ${ethers.formatEther(user1Position.yesBalance)}`);
  console.log(`   - User1 NO Balance: ${ethers.formatEther(user1Position.noBalance)}`);
  
  // 检查流动性价值
  const liquidityValue = await market.getLiquidityValue(0, user1.address);
  console.log(`💰 User1 Liquidity Value: ${ethers.formatEther(liquidityValue)} TEST`);

  liquidityInfo = await market.liqudityInfo(0);
  console.log(`💧 Liquidity Info:`);
  console.log(`   - Virtual Liquidity: ${ethers.formatEther(liquidityInfo.virtualLiquidity)}`);
  console.log(`   - lpCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.lpCollateralAmount)}`);
  console.log(`   - tradeCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.tradeCollateralAmount)}`);
  console.log(`   - totalFee: ${ethers.formatEther(liquidityInfo.totalFee)}`);
  console.log(`   - Total LP: ${ethers.formatEther(liquidityInfo.totalLp)}`);
  console.log(`   - yesAmount: ${ethers.formatEther(liquidityInfo.yesAmount)}`);
  console.log(`   - noAmount: ${ethers.formatEther(liquidityInfo.noAmount)}`);

  yesPrice = await market.getYesPrice(0);
  noPrice = await market.getNoPrice(0);
  console.log(`📈 YES Price: ${ethers.formatEther(yesPrice)}`);
  console.log(`📉 NO Price: ${ethers.formatEther(noPrice)}`);

  console.log("\n🎯 Step 6: Testing Buy Operations...");
  
  // 用户2购买YES
  const user2BuyAmount = ethers.parseEther("100");
  await token.connect(user2).approve(marketAddress, user2BuyAmount);
  console.log(`✅ User2 approved ${ethers.formatEther(user2BuyAmount)} TEST tokens for buying`);
  
  const buyYesTx = await market.connect(user2).buy(1, user2BuyAmount, 0); // 1 = Bet.Yes
  await buyYesTx.wait();
  console.log(`✅ User2 bought ${ethers.formatEther(user2BuyAmount)} worth of YES tokens`);

  let finalYesPrice = await market.getYesPrice(0);
  let finalNoPrice = await market.getNoPrice(0);
  console.log(`📈 Final YES Price: ${ethers.formatEther(finalYesPrice)}`);
  console.log(`📉 Final NO Price: ${ethers.formatEther(finalNoPrice)}`);

  liquidityInfo = await market.liqudityInfo(0);
  console.log(`💧 Liquidity Info:`);
  console.log(`   - Virtual Liquidity: ${ethers.formatEther(liquidityInfo.virtualLiquidity)}`);
  console.log(`   - lpCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.lpCollateralAmount)}`);
  console.log(`   - tradeCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.tradeCollateralAmount)}`);
  console.log(`   - totalFee: ${ethers.formatEther(liquidityInfo.totalFee)}`);
  console.log(`   - Total LP: ${ethers.formatEther(liquidityInfo.totalLp)}`);
  console.log(`   - yesAmount: ${ethers.formatEther(liquidityInfo.yesAmount)}`);
  console.log(`   - noAmount: ${ethers.formatEther(liquidityInfo.noAmount)}`);
  
  const user2PositionAfterBuy = await market.userPosition(user2.address, 0);
  console.log(`📊 User2 Position after buying YES:`);
  console.log(`   - YES Balance: ${ethers.formatEther(user2PositionAfterBuy.yesBalance)}`);
  console.log(`   - NO Balance: ${ethers.formatEther(user2PositionAfterBuy.noBalance)}`);

  // 用户2购买NO
  const user2BuyNoAmount = ethers.parseEther("125");
  await token.connect(user2).approve(marketAddress, user2BuyNoAmount);
  
  // const buyNoTx = await market.connect(user2).buy(2, user2BuyNoAmount, 0); // 2 = Bet.No
  // await buyNoTx.wait();
  // console.log(`✅ User2 bought ${ethers.formatEther(user2BuyNoAmount)} worth of NO tokens`);

  finalYesPrice = await market.getYesPrice(0);
  finalNoPrice = await market.getNoPrice(0);
  console.log(`📈 Final YES Price: ${ethers.formatEther(finalYesPrice)}`);
  console.log(`📉 Final NO Price: ${ethers.formatEther(finalNoPrice)}`);

  liquidityInfo = await market.liqudityInfo(0);
  console.log(`💧 Liquidity Info:`);
  console.log(`   - Virtual Liquidity: ${ethers.formatEther(liquidityInfo.virtualLiquidity)}`);
  console.log(`   - lpCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.lpCollateralAmount)}`);
  console.log(`   - tradeCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.tradeCollateralAmount)}`);
  console.log(`   - totalFee: ${ethers.formatEther(liquidityInfo.totalFee)}`);
  console.log(`   - Total LP: ${ethers.formatEther(liquidityInfo.totalLp)}`);
  console.log(`   - yesAmount: ${ethers.formatEther(liquidityInfo.yesAmount)}`);
  console.log(`   - noAmount: ${ethers.formatEther(liquidityInfo.noAmount)}`);
  
  const user2PositionFinal = await market.userPosition(user2.address, 0);
  console.log(`📊 User2 Final Position:`);
  console.log(`   - YES Balance: ${ethers.formatEther(user2PositionFinal.yesBalance)}`);
  console.log(`   - NO Balance: ${ethers.formatEther(user2PositionFinal.noBalance)}`);

  console.log("\n🎯 Step 7: Testing Sell Operations...");
  
  // 用户2出售全部YES
  const balance1 = await token.balanceOf(user2.address);
  const sellYesAmount = user2PositionFinal.yesBalance;
  const sellYesTx = await market.connect(user2).sell(1, sellYesAmount, 0);
  await sellYesTx.wait();
  console.log(`✅ User2 sold ${ethers.formatEther(sellYesAmount)} YES tokens`);
  const balance2 = await token.balanceOf(user2.address);
  console.log(`💰 User1 received ${ethers.formatEther(balance2 - balance1)}`);

  finalYesPrice = await market.getYesPrice(0);
  finalNoPrice = await market.getNoPrice(0);
  console.log(`📈 Final YES Price: ${ethers.formatEther(finalYesPrice)}`);
  console.log(`📉 Final NO Price: ${ethers.formatEther(finalNoPrice)}`);

  liquidityInfo = await market.liqudityInfo(0);
  console.log(`💧 Liquidity Info:`);
  console.log(`   - Virtual Liquidity: ${ethers.formatEther(liquidityInfo.virtualLiquidity)}`);
  console.log(`   - lpCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.lpCollateralAmount)}`);
  console.log(`   - tradeCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.tradeCollateralAmount)}`);
  console.log(`   - totalFee: ${ethers.formatEther(liquidityInfo.totalFee)}`);
  console.log(`   - Total LP: ${ethers.formatEther(liquidityInfo.totalLp)}`);
  console.log(`   - yesAmount: ${ethers.formatEther(liquidityInfo.yesAmount)}`);
  console.log(`   - noAmount: ${ethers.formatEther(liquidityInfo.noAmount)}`);
  
  const user2PositionAfterSell = await market.userPosition(user2.address, 0);
  console.log(`📊 User2 Position after selling YES:`);
  console.log(`   - YES Balance: ${ethers.formatEther(user2PositionAfterSell.yesBalance)}`);
  console.log(`   - NO Balance: ${ethers.formatEther(user2PositionAfterSell.noBalance)}`);

  console.log("\n🎯 Step 8: Testing Liquidity Removal...");
  
  // 用户1移除部分流动性
  const removeLiquidityAmount = user1Position.lp / 3n;
  const user1BalanceBefore = await token.balanceOf(user1.address);
  
  const removeLiqTx = await market.connect(user1).removeLiquidity(0, removeLiquidityAmount);
  await removeLiqTx.wait();
  console.log(`✅ User1 removed ${ethers.formatEther(removeLiquidityAmount)} liquidity`);

  finalYesPrice = await market.getYesPrice(0);
  finalNoPrice = await market.getNoPrice(0);
  console.log(`📈 Final YES Price: ${ethers.formatEther(finalYesPrice)}`);
  console.log(`📉 Final NO Price: ${ethers.formatEther(finalNoPrice)}`);
  
  const user1BalanceAfter = await token.balanceOf(user1.address);
  const profit = user1BalanceAfter - user1BalanceBefore;
  console.log(`💰 User1 received ${ethers.formatEther(profit)} TEST tokens from liquidity removal`);
  
  const user1PositionFinal = await market.userPosition(user1.address, 0);
  console.log(`📊 User1 Final Position:`);
  console.log(`   - LP: ${ethers.formatEther(user1PositionFinal.lp)}`);
  console.log(`   - YES Balance: ${ethers.formatEther(user1PositionFinal.yesBalance)}`);
  console.log(`   - NO Balance: ${ethers.formatEther(user1PositionFinal.noBalance)}`);

  console.log("\n🎯 Step 9: Testing Estimation Functions...");
  
  // 测试流动性移除预估
  const estimation = await market.connect(user1).estimateLiquidityRemoval(0, user1PositionFinal.lp);
  console.log(`   - Fee Share: ${ethers.formatEther(estimation.feeShare)}`);
  console.log(`   - Total Value: ${ethers.formatEther(estimation.totalValue)}`);

  // 最终市场状态
  const finalLiquidityInfo = await market.liqudityInfo(0);
  console.log("\n📊 Final Market State:");
  console.log(`   - Total LP: ${ethers.formatEther(finalLiquidityInfo.totalLp)}`);
  console.log(`   - YES Amount: ${ethers.formatEther(finalLiquidityInfo.yesAmount)}`);
  console.log(`   - NO Amount: ${ethers.formatEther(finalLiquidityInfo.noAmount)}`);
  console.log(`   - Total Fee: ${ethers.formatEther(finalLiquidityInfo.totalFee)}`);
  console.log(`   - lpCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.lpCollateralAmount)}`);
  console.log(`   - tradeCollateralAmount Amount: ${ethers.formatEther(liquidityInfo.tradeCollateralAmount)}`);

  finalYesPrice = await market.getYesPrice(0);
  finalNoPrice = await market.getNoPrice(0);
  console.log(`📈 Final YES Price: ${ethers.formatEther(finalYesPrice)}`);
  console.log(`📉 Final NO Price: ${ethers.formatEther(finalNoPrice)}`);

  console.log("\n🎉 All tests completed successfully!");
  console.log("\n📋 Contract Addresses:");
  console.log(`   - MockERC20: ${tokenAddress}`);
  console.log(`   - AroundMarket: ${marketAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });