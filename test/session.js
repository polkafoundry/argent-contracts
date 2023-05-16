/* global artifacts */

const ethers = require("ethers");
const chai = require("chai");
const BN = require("bn.js");
const bnChai = require("bn-chai");

const { assert, expect } = chai;
chai.use(bnChai(BN));

const truffleAssert = require("truffle-assertions");

const BaseWallet = artifacts.require("BaseWallet");
const Registry = artifacts.require("ModuleRegistry");
const TransferStorage = artifacts.require("TransferStorage");
const GuardianStorage = artifacts.require("GuardianStorage");
// const ArgentModule = artifacts.require("ArgentModule");
const DappRegistry = artifacts.require("DappRegistry");
const ERC20 = artifacts.require("TestERC20");
const UniswapV2Router01 = artifacts.require("DummyUniV2Router");
const WalletFactory = artifacts.require("WalletFactory");

const utils = require("../utils/utilities.js");
const { ETH_TOKEN, encodeTransaction, initNonce } = require("../utils/utilities.js");

const ZERO_BYTES = "0x";
const ZERO_ADDRESS = ethers.constants.AddressZero;
const SECURITY_PERIOD = 2;
const SECURITY_WINDOW = 2;
const LOCK_PERIOD = 4;
const RECOVERY_PERIOD = 4;

const RelayManager = require("../utils/relay-manager");

contract("ArgentModule sessions", (accounts) => {
  let manager;

  const infrastructure = accounts[0];
  const owner = accounts[1];
  const guardian1 = accounts[2];
  const recipient = accounts[4];
  const sessionUser = accounts[6];
  const sessionUser2 = accounts[7];
  const refundAddress = accounts[8];
  const relayer = accounts[9];

  let registry;
  let transferStorage;
  let guardianStorage;
  let module;
  let wallet;
  let dappRegistry;
  let token;
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

    await registry.registerModule(module.address, ethers.utils.formatBytes32String("ArgentModule"));
    await dappRegistry.addDapp(0, relayer, ZERO_ADDRESS);

    const walletImplementation = await BaseWallet.new();
    factory = await WalletFactory.new(
      walletImplementation.address,
      guardianStorage.address,
      refundAddress);
    await factory.addManager(infrastructure);

    manager = new RelayManager(guardianStorage.address, ZERO_ADDRESS);
    token = await ERC20.new([infrastructure], web3.utils.toWei("10000"), 19);
  });

  beforeEach(async () => {
    const walletAddress = await utils.createWallet(factory.address, owner, [module.address], guardian1);
    wallet = await BaseWallet.at(walletAddress);

    await wallet.send(new BN("1000000000000000000"));

    await initNonce(wallet, module, manager, SECURITY_PERIOD);
  });

  describe("session lifecycle", () => {
    it("owner plus majority guardians should be able to start a session", async () => {
      const txReceipt = await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 1000],
        wallet,
        [owner, guardian1],
        1,
        ETH_TOKEN,
        recipient);

      const { success } = utils.parseRelayReceipt(txReceipt);
      assert.isTrue(success);

      const session = await module.getSession(wallet.address);
      assert.equal(session.key, sessionUser);

      const timestamp = await utils.getTimestamp(txReceipt.blockNumber);
      expect(session.expires).to.eq.BN(timestamp + 1000);

      console.log(`Gas for starting a session: ${txReceipt.gasUsed}`);
    });

    it("should be able to overwrite an existing session", async () => {
      await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 1000],
        wallet,
        [owner, guardian1],
        1,
        ETH_TOKEN,
        recipient);

      // Start another session on the same wallet for sessionUser2 with duration 2000s
      const txReceipt = await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser2, 2000],
        wallet,
        [owner, guardian1],
        1,
        ETH_TOKEN,
        recipient);

      const { success } = utils.parseRelayReceipt(txReceipt);
      assert.isTrue(success);

      const session = await module.getSession(wallet.address);
      assert.equal(session.key, sessionUser2);

      const timestamp = await utils.getTimestamp(txReceipt.blockNumber);
      expect(session.expires).to.eq.BN(timestamp + 2000);
    });

    it("should not be able to start a session for empty user address", async () => {
      const txReceipt = await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], ZERO_ADDRESS, 1000],
        wallet,
        [owner, guardian1],
        1,
        ETH_TOKEN,
        recipient);

      const { success, error } = utils.parseRelayReceipt(txReceipt);
      assert.isFalse(success);
      assert.equal(error, "TM: Invalid session user");
    });

    it("should not be able to start a session for zero duration", async () => {
      const txReceipt = await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 0],
        wallet,
        [owner, guardian1],
        1,
        ETH_TOKEN,
        recipient);

      const { success, error } = utils.parseRelayReceipt(txReceipt);
      assert.isFalse(success);
      assert.equal(error, "TM: Invalid session duration");
    });

    it("owner should be able to clear a session", async () => {
      // Start a session for sessionUser with duration 1000s
      await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 1000],
        wallet,
        [owner, guardian1],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);

      // owner clears the session
      const txReceipt = await manager.relay(
        module,
        "clearSession",
        [wallet.address],
        wallet,
        [owner],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);

      const { success } = utils.parseRelayReceipt(txReceipt);
      assert.isTrue(success);

      const session = await module.getSession(wallet.address);
      assert.equal(session.key, ZERO_ADDRESS);

      expect(session.expires).to.eq.BN(0);
    });

    it("non-owner should not be able to clear a session", async () => {
      // Start a session for sessionUser with duration 1000s
      await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 1000],
        wallet,
        [owner, guardian1],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);

      // owner clears the session
      await truffleAssert.reverts(manager.relay(
        module,
        "clearSession",
        [wallet.address],
        wallet,
        [accounts[8]],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS), "RM: Invalid signatures");
    });

    it("should not be able to clear a session when wallet is locked", async () => {
      // Start a session for sessionUser with duration 1000s
      await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 1000],
        wallet,
        [owner, guardian1],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);

      // Lock wallet
      await module.lock(wallet.address, { from: guardian1 });

      // owner clears the session
      const txReceipt = await manager.relay(
        module,
        "clearSession",
        [wallet.address],
        wallet,
        [owner],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);

      const { success, error } = utils.parseRelayReceipt(txReceipt);
      assert.isFalse(success);
      assert.equal(error, "BM: wallet locked");
    });
  });

  describe("approved transfer (without using a session)", () => {
    it("should be able to send ETH with guardians", async () => {
      const transaction = encodeTransaction(recipient, 10, ZERO_BYTES);

      const balanceBefore = await utils.getBalance(recipient);
      const txReceipt = await manager.relay(
        module,
        "multiCallWithGuardians",
        [wallet.address, [transaction]],
        wallet,
        [owner, guardian1],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);
      const success = await utils.parseRelayReceipt(txReceipt).success;
      assert.isTrue(success);

      const balanceAfter = await utils.getBalance(recipient);
      expect(balanceAfter.sub(balanceBefore)).to.eq.BN(10);
      console.log(`Gas for send ETH with guardians: ${txReceipt.gasUsed}`);
    });

    it("should be able to transfer ERC20 with guardians", async () => {
      await token.transfer(wallet.address, 10);
      const data = await token.contract.methods.transfer(recipient, 10).encodeABI();
      const transaction = encodeTransaction(token.address, 0, data);

      const balanceBefore = await token.balanceOf(recipient);
      const txReceipt = await manager.relay(
        module,
        "multiCallWithGuardians",
        [wallet.address, [transaction]],
        wallet,
        [owner, guardian1],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);
      const success = await utils.parseRelayReceipt(txReceipt).success;
      assert.isTrue(success);

      const balanceAfter = await token.balanceOf(recipient);
      expect(balanceAfter.sub(balanceBefore)).to.eq.BN(10);
    });
  });

  describe("transfer using session", () => {
    beforeEach(async () => {
      // Create a session for sessionUser with duration 1000s to use in tests
      await manager.relay(
        module,
        "multiCallWithGuardiansAndStartSession",
        [wallet.address, [], sessionUser, 10000],
        wallet,
        [owner, guardian1],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);
    });

    it("should be able to send ETH", async () => {
      const transaction = encodeTransaction(recipient, 10, ZERO_BYTES);

      const balanceBefore = await utils.getBalance(recipient);
      const txReceipt = await manager.relay(
        module,
        "multiCallWithSession",
        [wallet.address, [transaction]],
        wallet,
        [sessionUser],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);
      const success = await utils.parseRelayReceipt(txReceipt).success;
      assert.isTrue(success);

      const balanceAfter = await utils.getBalance(recipient);
      expect(balanceAfter.sub(balanceBefore)).to.eq.BN(10);
    });

    it("should be able to transfer ERC20", async () => {
      await token.transfer(wallet.address, 10);
      const data = await token.contract.methods.transfer(recipient, 10).encodeABI();
      const transaction = encodeTransaction(token.address, 0, data);

      const balanceBefore = await token.balanceOf(recipient);
      const txReceipt = await manager.relay(
        module,
        "multiCallWithSession",
        [wallet.address, [transaction]],
        wallet,
        [sessionUser],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS);
      const success = await utils.parseRelayReceipt(txReceipt).success;
      assert.isTrue(success);

      const balanceAfter = await token.balanceOf(recipient);
      expect(balanceAfter.sub(balanceBefore)).to.eq.BN(10);
    });

    it("should not be able to send ETH with invalid session", async () => {
      const transaction = encodeTransaction(recipient, 10, ZERO_BYTES);

      await truffleAssert.reverts(manager.relay(
        module,
        "multiCallWithSession",
        [wallet.address, [transaction]],
        wallet,
        [sessionUser2],
        0,
        ZERO_ADDRESS,
        ZERO_ADDRESS), "RM: Invalid session");
    });
  });
});
