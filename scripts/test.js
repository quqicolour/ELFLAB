const { ethers } = require("hardhat");

async function main() {
  const [deployer, user1, user2] = await ethers.getSigners();
  console.log(`📝 Deployer address: ${deployer.address}`);
  console.log(`👤 User1 address: ${user1.address}`);
  console.log(`👤 User2 address: ${user2.address}`);

  const MockERC20 = await ethers.getContractFactory("TestToken");
  const USDC = await MockERC20.deploy(
    "Test Token",
    "TEST",
    ethers.parseEther("1000000")
  );
  const USDCAddress = USDC.target;
  console.log(`USDC: ${USDCAddress}`);

  const lmsrPredictionMarket = await ethers.getContractFactory(
    "LMSRPredictionMarket"
  );
  const LMSRPredictionMarket = await lmsrPredictionMarket.deploy(
    USDCAddress,
    "ETH TO 5000 IN 2025.12",
    100000,
    200000,
    ethers.parseEther("10000")
  );
  const LMSRPredictionMarketAddress = LMSRPredictionMarket.target;
  console.log("LMSRPredictionMarket:", LMSRPredictionMarketAddress);

  const approve = await USDC.approve(LMSRPredictionMarketAddress, ethers.parseEther("100000000000000"));
  const approvetx = await approve.wait();
  console.log("Approve tx:", approvetx.hash);

  const addLiquidity = await LMSRPredictionMarket.addLiquidity(ethers.parseEther("10000"));
  const addLiquidityTx = await addLiquidity.wait();
  console.log("addLiquidity:", addLiquidityTx.hash);

  const OutCome = {
    Yes: 0,
    No: 1
  };

  const calculateCost1 = await LMSRPredictionMarket.calculateCost(
    OutCome.Yes,
    ethers.parseEther("100")
  );
  console.log("calculateCost1:", calculateCost1);

  const buyShares = await LMSRPredictionMarket.buyShares(
    OutCome.Yes,
    ethers.parseEther("100")
  );
  const buySharesTx = await buyShares.wait();
  console.log("buyShares:", buySharesTx.hash);

  const getUserInfo1  = await LMSRPredictionMarket.getUserInfo(deployer.address);
  console.log("getUserInfo1:", getUserInfo1);

  const market1 = await LMSRPredictionMarket.market();
  console.log("market1:", market1);

  const sellShares = await LMSRPredictionMarket.sellShares(
    OutCome.Yes,
    getUserInfo1[1]
  );
  const sellSharesTx = await sellShares.wait();
  console.log("sellShares:", sellSharesTx.hash);

  const getUserInfo2  = await LMSRPredictionMarket.getUserInfo(deployer.address);
  console.log("getUserInfo2:", getUserInfo2);

  const market2 = await LMSRPredictionMarket.market();
  console.log("market2:", market2);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
