/* global artifacts */
const truffleAssert = require("truffle-assertions");
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
const UniswapV2Router01 = artifacts.require("DummyUniV2Router");

const utils = require("../utils/utilities.js");

const ZERO_ADDRESS = ethers.constants.AddressZero;
const SECURITY_PERIOD = 24;
const SECURITY_WINDOW = 12;
const LOCK_PERIOD = 50;
const RECOVERY_PERIOD = 36;

const RelayManager = require("../utils/relay-manager");

contract("SecurityManager", (accounts) => {
  let manager;

  const infrastructure = accounts[0];
  const owner = accounts[1];
  const guardian1 = accounts[2];
  const nonowner = accounts[7];
  const refundAddress = accounts[8];
  const relayer = accounts[9];

  let registry;
  let guardianStorage;
  let transferStorage;
  let module;
  let wallet;
  let noGuardianWallet;
  let walletImplementation;
  let factory;
  let dappRegistry;

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

    await registry.registerModule(module.address, ethers.utils.formatBytes32String("ArgentModule"));
    await dappRegistry.addDapp(0, relayer, ZERO_ADDRESS);

    walletImplementation = await BaseWallet.new();
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

    const noGuardianWalletAddress = await utils.createWallet(factory.address, owner, [module.address], ZERO_ADDRESS);
    noGuardianWallet = await BaseWallet.at(noGuardianWalletAddress);

    await noGuardianWallet.send(new BN("1000000000000000000"));
  });

  describe("Security Enabling", () => {
    it("should let the owner enable security", async () => {
      await module.enableSecurity(noGuardianWallet.address, { from: owner });
      const isSecurityEnabled = await guardianStorage.isSecurityEnabled(noGuardianWallet.address);
      assert.equal(isSecurityEnabled, true, "security should be enabled");
    });

    it("should let the owner enable security (relay tx)", async () => {
      await manager.relay(module, "enableSecurity", [noGuardianWallet.address], noGuardianWallet, [owner]);
      const isSecurityEnabled = await guardianStorage.isSecurityEnabled(noGuardianWallet.address);
      assert.equal(isSecurityEnabled, true, "security should be enabled");
    });

    it("should not let the non-owner enable security", async () => {
      await truffleAssert.reverts(module.enableSecurity(noGuardianWallet.address, { from: nonowner }),
        "BM: must be wallet owner/self");
    });

    it("should not be able to enable security, when security is already enabled", async () => {
      await truffleAssert.reverts(module.enableSecurity(wallet.address, { from: owner }),
        "BM: security enabled");
    });
  });

  describe("Security Disabling", () => {
    it("should let a majority of guardians (including owner) disable security (relay tx)", async () => {
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);
      let isSecurityEnabled = await guardianStorage.isSecurityEnabled(wallet.address);
      assert.equal(isSecurityEnabled, true, "security disabling should be pending during security period");
      await utils.increaseTime(30);

      await manager.relay(module, "confirmSecurityDisabling", [wallet.address], wallet, []);
      isSecurityEnabled = await guardianStorage.isSecurityEnabled(noGuardianWallet.address);
      assert.equal(isSecurityEnabled, false, "security should be disabled");
    });

    it("should let the owner disable security immediately if the wallet has no guardian", async () => {
      await manager.relay(module, "enableSecurity", [noGuardianWallet.address], noGuardianWallet, [owner]);
      let isSecurityEnabled = await guardianStorage.isSecurityEnabled(noGuardianWallet.address);
      assert.equal(isSecurityEnabled, true, "security should be enabled");
      await manager.relay(module, "disableSecurity", [noGuardianWallet.address], noGuardianWallet, [owner]);
      isSecurityEnabled = await guardianStorage.isSecurityEnabled(noGuardianWallet.address);
      assert.equal(isSecurityEnabled, false, "security should be disabled");
    });

    it("should not be able to disable security, when security is already disabled", async () => {
      const txReceipt = await manager.relay(module, "disableSecurity", [noGuardianWallet.address], noGuardianWallet, [owner]);
      const { success, error } = utils.parseRelayReceipt(txReceipt);
      assert.isFalse(success, "disableSecurity should have failed");
      assert.equal(error, "BM: security must be enabled");
    });

    it("should not let owner + minority of guardians", async () => {
      await truffleAssert.reverts(manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner]),
        "RM: Wrong number of signatures");
    });

    it("should not allow non guardian signatures", async () => {
      await truffleAssert.reverts(manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, nonowner]),
        "RM: Invalid signatures");
    });

    it("should not confirm security disabling too early", async () => {
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);
      await truffleAssert.reverts(module.confirmSecurityDisabling(wallet.address, { from: owner }),
        "SM: pending not over");
    });

    it("should not confirm a security disabling after two security periods (blockchain transaction)", async () => {
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);

      await utils.increaseTime(48); // 48 == 2 * security_period
      await truffleAssert.reverts(module.confirmSecurityDisabling(wallet.address, { from: owner }),
        "SM: pending expired");
    });

    it("should not be able to disable security twice", async () => {
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);
      const txReceipt = await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);
      const { success, error } = utils.parseRelayReceipt(txReceipt);
      assert.isFalse(success, "disableSecurity should have failed");
      assert.equal(error, "SM: duplicate disabling request");
    });

    it("should allow to request security disabling again after missing the confirmation window the first time", async () => {
      // first time
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);

      await utils.increaseTime(48); // 48 == 2 * security_period
      await truffleAssert.reverts(module.confirmSecurityDisabling(wallet.address, { from: owner }),
        "SM: pending expired");

      // second time
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);
      let isSecurityEnabled = await guardianStorage.isSecurityEnabled(wallet.address);
      assert.equal(isSecurityEnabled, true, "security should still be enabled during the security period");

      await utils.increaseTime(30);
      await module.confirmSecurityDisabling(wallet.address, { from: owner });
      isSecurityEnabled = await guardianStorage.isSecurityEnabled(wallet.address);
      assert.equal(isSecurityEnabled, false, "security should still be disabled");
    });
  });

  describe("Cancelling security disabling pending request", async () => {
    it("owner should be able to cancel pending security disabling request", async () => {
      // Add guardian 2 and cancel its addition
      await manager.relay(module, "disableSecurity", [wallet.address], wallet, [owner, guardian1]);
      await module.cancelSecurityDisabling(wallet.address, { from: owner });
      await utils.increaseTime(30);
      await truffleAssert.reverts(module.confirmSecurityDisabling(wallet.address, { from: owner }),
        "SM: unknown disabling request");
    });

    it("owner should not be able to cancel a nonexistent security disabling request", async () => {
      await truffleAssert.reverts(module.cancelSecurityDisabling(wallet.address, { from: owner }),
        "SM: unknown disabling request");
    });
  });

  describe("Storage", () => {
    it("should not allow non modules to setSecurityEnabled", async () => {
      await truffleAssert.reverts(guardianStorage.setSecurityEnabled(wallet.address, false),
        "TS: must be an authorized module to call this method");
    });
  });
});
