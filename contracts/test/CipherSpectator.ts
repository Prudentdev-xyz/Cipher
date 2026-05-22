import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import hre from "hardhat";

describe("CipherSpectator", async function () {
  let viem: any;
  let spectator: any;
  let config: any;
  let owner: any;
  let playerA: any;
  let playerB: any;
  let spec1: any;
  let spec2: any;
  let spec3: any;
  let treasury: any;

  before(async function () {
    const network = await hre.network.create();
    viem = network.viem;

    const wallets = await viem.getWalletClients();
    owner    = wallets[0];
    playerA  = wallets[1];
    playerB  = wallets[2];
    spec1    = wallets[3];
    spec2    = wallets[4];
    spec3    = wallets[5];
    treasury = wallets[6];

    config = await viem.deployContract("CipherConfig", [
      treasury.account.address,
    ]);

    spectator = await viem.deployContract("CipherSpectator", [
      config.address,
    ]);

    // Authorize owner as match contract for testing
    await spectator.write.addAuthorizedMatch([owner.account.address]);
  });

  it("should initialize a pool correctly", async function () {
    await spectator.write.initializePool([
      1n,
      playerA.account.address,
      playerB.account.address,
    ]);

    const pool = await spectator.read.getPool([1n]);
    assert.equal(pool.playerA.toLowerCase(), playerA.account.address.toLowerCase());
    assert.equal(pool.playerB.toLowerCase(), playerB.account.address.toLowerCase());
    assert.equal(pool.predictionsOpen, true);
    assert.equal(pool.resolved, false);
  });

  it("should allow spectator to watch a match", async function () {
    await spectator.write.watchMatch([1n], {
      account: spec1.account,
    });

    const count = await spectator.read.getWatcherCount([1n]);
    assert.equal(count, 1n);
  });

  it("should allow spectator to place prediction", async function () {
    await spectator.write.placePrediction(
      [1n, playerA.account.address],
      {
        account: spec1.account,
        value: 20000000000000000n, // 0.02 RITUAL
      }
    );

    const pool = await spectator.read.getPool([1n]);
    assert.equal(pool.poolForPlayerA, 20000000000000000n);
    assert.equal(pool.totalPool, 20000000000000000n);
  });

  it("should reject double prediction from same spectator", async function () {
    await assert.rejects(
      spectator.write.placePrediction(
        [1n, playerA.account.address],
        {
          account: spec1.account,
          value: 10000000000000000n,
        }
      )
    );
  });

  it("should reject prediction from match players", async function () {
    await assert.rejects(
      spectator.write.placePrediction(
        [1n, playerA.account.address],
        {
          account: playerA.account,
          value: 10000000000000000n,
        }
      )
    );
  });

  it("should allow second spectator to predict on playerB", async function () {
    await spectator.write.placePrediction(
      [1n, playerB.account.address],
      {
        account: spec2.account,
        value: 10000000000000000n, // 0.01 RITUAL
      }
    );

    const pool = await spectator.read.getPool([1n]);
    assert.equal(pool.poolForPlayerB, 10000000000000000n);
  });

  it("should lock predictions correctly", async function () {
    await spectator.write.closePredictions([1n]);

    const pool = await spectator.read.getPool([1n]);
    assert.equal(pool.predictionsOpen, false);
  });

  it("should reject prediction after lock", async function () {
    await assert.rejects(
      spectator.write.placePrediction(
        [1n, playerA.account.address],
        {
          account: spec3.account,
          value: 10000000000000000n,
        }
      )
    );
  });

  it("should resolve match and distribute payouts", async function () {
    // PlayerA wins — spec1 predicted correctly
    await spectator.write.resolveMatch([
      1n,
      playerA.account.address,
    ]);

    const pool = await spectator.read.getPool([1n]);
    assert.equal(pool.resolved, true);
    assert.equal(
      pool.winner.toLowerCase(),
      playerA.account.address.toLowerCase()
    );
  });

  it("should reject resolving already resolved match", async function () {
    await assert.rejects(
      spectator.write.resolveMatch([
        1n,
        playerA.account.address,
      ])
    );
  });

  it("should reject unauthorized caller on initializePool", async function () {
    await assert.rejects(
      spectator.write.initializePool(
        [2n, playerA.account.address, playerB.account.address],
        { account: spec1.account }
      )
    );
  });
});