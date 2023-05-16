/* global artifacts */

const ethers = require("ethers");
const chai = require("chai");
const BN = require("bn.js");
const bnChai = require("bn-chai");

const { assert } = chai;
chai.use(bnChai(BN));

const WalletFactory = artifacts.require("WalletFactory");
const BaseWallet = artifacts.require("BaseWallet");
const Registry = artifacts.require("ModuleRegistry");
const TransferStorage = artifacts.require("TransferStorage");
const GuardianStorage = artifacts.require("GuardianStorage");
// const ArgentModule = artifacts.require("ArgentModule");
const DappRegistry = artifacts.require("DappRegistry");
const Upgrader = artifacts.require("SimpleUpgrader");
const UniswapV2Router01 = artifacts.require("DummyUniV2Router");

const { initNonce, parseRelayReceipt } = require("../utils/utilities.js");

const ZERO_ADDRESS = ethers.constants.AddressZero;
const SECURITY_PERIOD = 2;
const SECURITY_WINDOW = 2;
const LOCK_PERIOD = 4;
const RECOVERY_PERIOD = 4;

const utils = require("../utils/utilities.js");
const RelayManager = require("../utils/relay-manager");

contract("TransactionManager", (accounts) => {
  let manager;

  const infrastructure = accounts[0];
  const owner = accounts[1];
  const guardian1 = accounts[2];
  const refundAddress = accounts[7];
  const relayer = accounts[9];

  let registry;

  let transferStorage;
  let guardianStorage;
  let module;
  let newModule;
  let upgrader1;
  let dappRegistry;

  let wallet;
  let factory;

  before(async () => {
    registry = await Registry.new();

    guardianStorage = await GuardianStorage.new();
    transferStorage = await TransferStorage.new();

    dappRegistry = await DappRegistry.new(0);

    const uniswapRouter = await UniswapV2Router01.new();

    module = await utils.deployArgentDiamond(
      infrastructure,
      registry.address,
      guardianStorage.address,
      transferStorage.address,
      dappRegistry.address,
      uniswapRouter.address,
      SECURITY_PERIOD,
      SECURITY_WINDOW,
      RECOVERY_PERIOD,
      LOCK_PERIOD);

    newModule = await utils.deployArgentDiamond(
      infrastructure,
      registry.address,
      guardianStorage.address,
      transferStorage.address,
      dappRegistry.address,
      uniswapRouter.address,
      SECURITY_PERIOD,
      SECURITY_WINDOW,
      RECOVERY_PERIOD,
      LOCK_PERIOD);

    upgrader1 = await Upgrader.new(
      registry.address,
      [newModule.address],
      [module.address]);

    await registry.registerModule(module.address, ethers.utils.formatBytes32String("ArgentMdoule"));
    await registry.registerModule(newModule.address, ethers.utils.formatBytes32String("NewArgentModule"));
    await registry.registerModule(upgrader1.address, ethers.utils.formatBytes32String("Upgrader"));

    await dappRegistry.addDapp(0, relayer, ZERO_ADDRESS);

    const walletImplementation = await BaseWallet.new();
    factory = await WalletFactory.new(
      walletImplementation.address,
      guardianStorage.address,
      refundAddress);
    await factory.addManager(infrastructure);

    manager = new RelayManager(guardianStorage.address, ZERO_ADDRESS);
  });

  beforeEach(async () => {
    // create wallet
    const walletAddress = await utils.createWallet(factory.address, owner, [module.address], guardian1);
    wallet = await BaseWallet.at(walletAddress);
    await wallet.send(new BN("1000000000000000000"));
  });

  describe("upgrader modules", () => {
    beforeEach(async () => {
      await initNonce(wallet, module, manager, SECURITY_PERIOD);
    });

    it("should remove 1 and add 1 module", async () => {
      let isAuthorised = await wallet.authorised(newModule.address);
      assert.equal(isAuthorised, false, "new module should not be authorised");

      const txReceipt = await manager.relay(
        module,
        "addModule",
        [wallet.address, upgrader1.address],
        wallet,
        [owner]);
      const success = await parseRelayReceipt(txReceipt).success;
      assert.isTrue(success, "transfer failed");
      isAuthorised = await wallet.authorised(newModule.address);
      assert.equal(isAuthorised, false, "new module should be authorised");
      console.log("GAS for upgrade: ", txReceipt.gasUsed);
    });
  });
});
