const { ZeroAddress } = require("ethers");
const { ethers } = require("hardhat");

const Set = require("../set.json");

async function main() {
  console.log("🚀 Starting AroundMarket deployment and full test...\n");

  const [deployer, user1, user2] = await ethers.getSigners();
  console.log(`📝 Deployer address: ${deployer.address}`);
  console.log(`👤 User1 address: ${user1.address}`);
  console.log(`👤 User2 address: ${user2.address}`);

  const MARKET_FEE = 600; // 0.6%
  const PERIOD = 7 * 24 * 60 * 60; // 7 days
  const VIRTUAL_LIQUIDITY = ethers.parseEther("1000");
  const COLLATERAL_AMOUNT = 0;
  const QUEST = "Will ETH price reach $5000 by the end of 2024?";

  console.log(
    "\n ====================Deploying====================================="
  );

  const MockERC20 = await ethers.getContractFactory("TestToken");
  const USDC = await MockERC20.deploy(
    "Test USDC",
    "TUSDC",
    ethers.parseEther("1000000")
  );
  const USDCAddress = USDC.target;
  console.log(`✅ USDC deployed to: ${USDCAddress}`);

  await USDC.transfer(user1.address, ethers.parseEther("10000"));
  await USDC.transfer(user2.address, ethers.parseEther("10000"));

  const aroundPoolFactory = await ethers.getContractFactory(
    "AroundPoolFactory"
  );
  const AroundPoolFactory = await aroundPoolFactory.deploy(
    Set["Base_Sepolia"].AavePool,
    Set["Base_Sepolia"].AUSDC,
    Set["Base_Sepolia"].AaveProtocolDataProvider
  );
  const AroundPoolFactoryAddress = AroundPoolFactory.target;
  console.log(`✅ AroundPoolFactory deployed to: ${AroundPoolFactoryAddress}`);

  const aroundMarket = await ethers.getContractFactory("AroundMarket");
  const AroundMarket = await aroundMarket.deploy();
  const AroundMarketAddress = AroundMarket.target;
  console.log(`✅ AroundMarket deployed to: ${AroundMarketAddress}`);

  const echoOptimisticOracle = await ethers.getContractFactory(
    "EchoOptimisticOracle"
  );
  const EchoOptimisticOracle = await echoOptimisticOracle.deploy();
  const EchoOptimisticOracleAddress = EchoOptimisticOracle.target;
  console.log(
    `✅ EchoOptimisticOracle deployed to: ${EchoOptimisticOracleAddress}`
  );

  console.log(
    "\n ====================================Initialize========================================"
  );
  //TODO MultiSig
  const AroundPoolFactoryInitialize = await AroundPoolFactory.initialize(
    AroundMarketAddress
  );
  const AroundPoolFactoryInitializeTx =
    await AroundPoolFactoryInitialize.wait();
  console.log(
    "AroundPoolFactory Initialize:",
    AroundPoolFactoryInitializeTx.hash
  );

  const AroundMarketInitialize = await AroundMarket.initialize(
    deployer.address,
    AroundPoolFactoryAddress,
    EchoOptimisticOracleAddress
  );
  const AroundMarketInitializeTx = await AroundMarketInitialize.wait();
  console.log("AroundMarket Initialize:", AroundMarketInitializeTx.hash);

  const EchoOptimisticOracleInitialize = await EchoOptimisticOracle.initialize(AroundMarketAddress);
  const EchoOptimisticOracleInitializeTx = await EchoOptimisticOracleInitialize.wait();
  console.log("EchoOptimisticOracleInitialize initialize:", EchoOptimisticOracleInitializeTx.hash);

  const setTokenInfo = await AroundMarket.connect(deployer).setTokenInfo(
    USDCAddress,
    true,
    ethers.parseEther("10")
  );
  const setTokenInfoTx = await setTokenInfo.wait();
  console.log("AroundMarket setTokenInfo:", setTokenInfoTx.hash);

  console.log(
    "\n =============================Testing Market Creation================================="
  );

  async function CreatePool(collateral) {
    try {
      const createPool = await AroundPoolFactory.createPool(collateral);
      const createPoolTx = await createPool.wait();
      console.log("createPool:", createPoolTx.hash);
    } catch (e) {
      console.log("Create Pool fail:", e);
    }
  }

  async function CreateMarket(
    thisPeriod,
    thisExpectVirtualLiquidity,
    thisQuest,
    id
  ) {
    try {
      const CreateMarketParams = {
        period: thisPeriod,
        expectVirtualLiquidity: thisExpectVirtualLiquidity,
        quest: thisQuest,
        thisMarketId: id,
      };
      const createMarket = await AroundMarket.createMarket(CreateMarketParams);
      const createMarketTx = await createMarket.wait();
      console.log("createMarket:", createMarketTx.hash);
    } catch (e) {
      console.log("createMarket fail:", e);
    }
  }

  await USDC.approve(AroundMarketAddress, ethers.parseEther("1000000000000"));
  await CreatePool(USDCAddress);
  await CreateMarket(100000, 100000, "ETH TO 5000 USDC IN 2025.12.31", 0);

  let marketInfo = await AroundMarket.getMarketInfo(0);
  console.log(`📊 Market Info:`, marketInfo);

  let liquidityInfo = await AroundMarket.getLiqudityInfo(0);
  console.log(`📊 Liquidity Info:`, liquidityInfo);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
