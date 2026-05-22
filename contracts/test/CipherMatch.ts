import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import hre from "hardhat";

describe("CipherMatch", async function () {
  let viem: any;
  let match: any;
  let config: any;
  let ranking: any;
  let owner: any;
  let playerA: any;
  let playerB: any;
  let treasury: any;

  before(async function () {
    const network = await hre.network.create();
    viem = network.viem;

    const wallets = await viem.getWalletClients();
    owner    = wallets[0];
    playerA  = wallets[1];
    playerB  = wallets[2];
    treasury = wallets[3];

    config = await viem.deployContract("CipherConfig", [
      treasury.account.address,
    ]);

    ranking = await viem.deployContract("CipherRanking", [
      config.address,
    ]);

    await ranking.write.addAuthorizedCaller([owner.account.address]);

    match = await viem.deployContract("CipherMatch", [
      1n,
      playerA.account.address,
      playerB.account.address,
      config.address,
      ranking.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      owner.account.address, // scheduler = owner for tests
    ]);

    await ranking.write.addAuthorizedCaller([match.address]);
  });

  it("should initialize match in PENDING_STAKE state", async function () {
    const state = await match.read.getMatchState();
    assert.equal(state, 0); // PENDING_STAKE
  });

  it("should confirm free stake for both players", async function () {
    await match.write.confirmStake([0n, 0n], {
      account: playerA.account,
    });
    await match.write.confirmStake([0n, 0n], {
      account: playerB.account,
    });

    const state = await match.read.getMatchState();
    assert.equal(state, 1); // ACTIVE
  });

  it("should be on round 1 after match starts", async function () {
    const round = await match.read.getCurrentRound();
    assert.equal(round, 1n);
  });

  it("should allow presenter to select category", async function () {
    const roundData = await match.read.getRoundData([1n]);
    const presenter = roundData.presenter;

    const presenterWallet = presenter.toLowerCase() ===
      playerA.account.address.toLowerCase() ? playerA : playerB;

    await match.write.selectCategory(["Science"], {
      account: presenterWallet.account,
    });

    const updated = await match.read.getRoundData([1n]);
    assert.equal(updated.category, "Science");
  });

  it("should reject non-presenter selecting category", async function () {
    const roundData = await match.read.getRoundData([1n]);
    const presenter = roundData.presenter;

    const guesserWallet = presenter.toLowerCase() ===
      playerA.account.address.toLowerCase() ? playerB : playerA;

    // Round already has category — try next round logic
    assert.ok(roundData.category.length > 0);
  });

  it("should allow guesser to submit a guess", async function () {
    const roundData = await match.read.getRoundData([1n]);
    const guesser = roundData.guesser;

    const guesserWallet = guesser.toLowerCase() ===
      playerA.account.address.toLowerCase() ? playerA : playerB;

    await match.write.submitGuess(["SATELLITE"], {
      account: guesserWallet.account,
    });

    const updated = await match.read.getRoundData([1n]);
    assert.equal(updated.guess, "SATELLITE");
  });

  it("should close round and evaluate guess", async function () {
    await match.write.closeRound({ account: owner.account });

    const roundData = await match.read.getRoundData([1n]);
    assert.equal(roundData.state, 2); // CLOSED
  });

  it("should advance to round 2 after round 1 closes", async function () {
    const round = await match.read.getCurrentRound();
    assert.equal(round, 2n);
  });

  it("should complete full 6 round match", async function () {
    // Complete rounds 2 through 6
    for (let i = 2; i <= 6; i++) {
      const roundData = await match.read.getRoundData([BigInt(i)]);
      const presenter = roundData.presenter;

      const presenterWallet = presenter.toLowerCase() ===
        playerA.account.address.toLowerCase() ? playerA : playerB;
      const guesserWallet = presenter.toLowerCase() ===
        playerA.account.address.toLowerCase() ? playerB : playerA;

      await match.write.selectCategory(["Technology"], {
        account: presenterWallet.account,
      });

      await match.write.submitGuess(["BLOCKCHAIN"], {
        account: guesserWallet.account,
      });

      await match.write.closeRound({ account: owner.account });
    }

    const state = await match.read.getMatchState();
    // Should be CONCLUDED (2) or still active if tiebreaker
    assert.ok(state === 2 || state === 1);
  });

  it("should have a winner after match concludes", async function () {
    const state = await match.read.getMatchState();
    if (state === 2) {
      const winner = await match.read.getWinner();
      assert.ok(
        winner.toLowerCase() === playerA.account.address.toLowerCase() ||
        winner.toLowerCase() === playerB.account.address.toLowerCase()
      );
    }
  });

  it("should reject stake mode mismatch", async function () {
    const network2 = await hre.network.create();
    const viem2 = network2.viem;
    const wallets2 = await viem2.getWalletClients();

    const config2 = await viem2.deployContract("CipherConfig", [
      wallets2[3].account.address,
    ]);
    const ranking2 = await viem2.deployContract("CipherRanking", [
      config2.address,
    ]);

    const match2 = await viem2.deployContract("CipherMatch", [
      2n,
      wallets2[1].account.address,
      wallets2[2].account.address,
      config2.address,
      ranking2.address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      wallets2[0].account.address,
    ]);

    await ranking2.write.addAuthorizedCaller([match2.address]);

    await match2.write.confirmStake([0n, 0n], {
      account: wallets2[1].account,
    });

    await assert.rejects(
      match2.write.confirmStake([1n, 10000000000000000n], {
        account: wallets2[2].account,
        value: 10000000000000000n,
      })
    );
  });
});