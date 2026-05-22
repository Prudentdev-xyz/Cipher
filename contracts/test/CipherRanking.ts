import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import hre from "hardhat";

describe("CipherRanking", async function () {
  let viem: any;
  let ranking: any;
  let config: any;
  let owner: any;
  let playerA: any;
  let playerB: any;
  let unauthorized: any;

  before(async function () {
    const network = await hre.network.create();
    viem = network.viem;

    const wallets = await viem.getWalletClients();
    owner = wallets[0];
    playerA = wallets[1];
    playerB = wallets[2];
    unauthorized = wallets[3];

    config = await viem.deployContract("CipherConfig", [
      owner.account.address,
    ]);

    ranking = await viem.deployContract("CipherRanking", [
      config.address,
    ]);
  });

  it("should initialize a player correctly", async function () {
    await ranking.write.initializePlayer([playerA.account.address]);
    const data = await ranking.read.getPlayerRank([playerA.account.address]);
    assert.equal(data.totalPoints, 0n);
    assert.equal(data.tier, 0); // NOVICE
    assert.equal(data.wins, 0n);
    assert.equal(data.initialized, true);
  });

  it("should reject double initialization", async function () {
    await assert.rejects(
      ranking.write.initializePlayer([playerA.account.address])
    );
  });

  it("should update ranking after free match", async function () {
    await ranking.write.initializePlayer([playerB.account.address]);

    await ranking.write.updateRanking([
      playerA.account.address,
      playerB.account.address,
      0n, // FREE mode
      0n, // no tokens
    ]);

    const winnerData = await ranking.read.getPlayerRank([playerA.account.address]);
    const loserData = await ranking.read.getPlayerRank([playerB.account.address]);

    assert.equal(winnerData.wins, 1n);
    assert.equal(winnerData.totalPoints, 100n); // base win points
    assert.equal(loserData.losses, 1n);
  });

  it("should apply token match bonus", async function () {
    const wallets = await viem.getWalletClients();
    const playerC = wallets[4];
    const playerD = wallets[5];

    await ranking.write.initializePlayer([playerC.account.address]);
    await ranking.write.initializePlayer([playerD.account.address]);

    await ranking.write.updateRanking([
      playerC.account.address,
      playerD.account.address,
      1n, // TOKEN mode
      0n,
    ]);

    const data = await ranking.read.getPlayerRank([playerC.account.address]);
    assert.equal(data.totalPoints, 120n); // 100 + 20% bonus
  });

  it("should upgrade tier when points threshold reached", async function () {
    const wallets = await viem.getWalletClients();
    const playerE = wallets[6];
    const playerF = wallets[7];

    await ranking.write.initializePlayer([playerE.account.address]);
    await ranking.write.initializePlayer([playerF.account.address]);

    // Run 10 matches to push past SOLVER threshold (1000 points)
    for (let i = 0; i < 10; i++) {
      await ranking.write.updateRanking([
        playerE.account.address,
        playerF.account.address,
        1n,
        0n,
      ]);
    }

    const data = await ranking.read.getPlayerRank([playerE.account.address]);
    assert.equal(data.tier, 1); // SOLVER
  });

  it("should reject unauthorized callers", async function () {
    await assert.rejects(
      ranking.write.updateRanking(
        [
          playerA.account.address,
          playerB.account.address,
          0n,
          0n,
        ],
        { account: unauthorized.account }
      )
    );
  });

  it("should return leaderboard sorted by points", async function () {
    const [addrs, data] = await ranking.read.getLeaderboard([5n]);
    assert.ok(addrs.length > 0);
    // Verify sorted descending
    for (let i = 0; i < data.length - 1; i++) {
      assert.ok(data[i].totalPoints >= data[i + 1].totalPoints);
    }
  });

  it("should return correct tier thresholds", async function () {
    assert.equal(await ranking.read.getTierThreshold([1]), 1000n); // SOLVER
    assert.equal(await ranking.read.getTierThreshold([2]), 3000n); // DECODER
    assert.equal(await ranking.read.getTierThreshold([3]), 6000n); // CRYPTIC
    assert.equal(await ranking.read.getTierThreshold([4]), 10000n); // CIPHER_ELITE
  });
});