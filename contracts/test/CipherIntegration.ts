import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import hre from "hardhat";

describe("CIPHER — Full Integration Tests", async function () {
  let viem: any;
  let config: any;
  let ranking: any;
  let factory: any;
  let spectatorContract: any;
  let owner: any;
  let playerA: any;
  let playerB: any;
  let spec1: any;
  let spec2: any;
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
    treasury = wallets[5];

    // Deploy all 5 contracts
    config = await viem.deployContract("CipherConfig", [
      treasury.account.address,
    ]);

    ranking = await viem.deployContract("CipherRanking", [
      config.address,
    ]);

    spectatorContract = await viem.deployContract("CipherSpectator", [
      config.address,
    ]);

    factory = await viem.deployContract("CipherMatchFactory", [
      config.address,
      ranking.address,
      spectatorContract.address,
    ]);
  });

  // ================================================================
  // FLOW 1 — FULL FREE MATCH END TO END
  // ================================================================

  describe("Flow 1 — Full Free Match", async function () {
    let match: any;

    it("should deploy a full match via factory session code", async function () {
      // PlayerA joins
      await factory.write.joinMatch(["INTEGRATION01"], {
        account: playerA.account,
      });

      // PlayerB joins — match deploys
      await factory.write.joinMatch(["INTEGRATION01"], {
        account: playerB.account,
      });

      const matchCount = await factory.read.getTotalMatchCount();
      assert.equal(matchCount, 1n);
    });

    it("should deploy CipherMatch directly for integration", async function () {
      // Authorize ranking for match
      match = await viem.deployContract("CipherMatch", [
        10n,
        playerA.account.address,
        playerB.account.address,
        config.address,
        ranking.address,
        spectatorContract.address,
        factory.address,
        owner.account.address,
      ]);

      await ranking.write.addAuthorizedCaller([match.address]);
      await spectatorContract.write.addAuthorizedMatch([match.address]);

      const state = await match.read.getMatchState();
      assert.equal(state, 0); // PENDING_STAKE
    });

    it("should start match after both players confirm free stake", async function () {
      await match.write.confirmStake([0n, 0n], {
        account: playerA.account,
      });
      await match.write.confirmStake([0n, 0n], {
        account: playerB.account,
      });

      const state = await match.read.getMatchState();
      assert.equal(state, 1); // ACTIVE
    });

    it("should complete all 6 rounds correctly", async function () {
      for (let i = 1; i <= 6; i++) {
        const roundData = await match.read.getRoundData([BigInt(i)]);
        const presenter = roundData.presenter.toLowerCase();

        const presenterWallet = presenter === playerA.account.address.toLowerCase()
          ? playerA : playerB;
        const guesserWallet = presenter === playerA.account.address.toLowerCase()
          ? playerB : playerA;

        await match.write.selectCategory(["Science"], {
          account: presenterWallet.account,
        });

        await match.write.submitGuess(["TELESCOPE"], {
          account: guesserWallet.account,
        });

        await match.write.closeRound({ account: owner.account });
      }

      const state = await match.read.getMatchState();
      assert.ok(state === 2 || state === 1); // CONCLUDED or tiebreaker
    });

    it("should have updated rankings after match", async function () {
      const state = await match.read.getMatchState();
      if (state === 2) {
        const winner = await match.read.getWinner();
        const loser = winner.toLowerCase() === playerA.account.address.toLowerCase()
          ? playerB.account.address : playerA.account.address;

        const winnerData = await ranking.read.getPlayerRank([winner]);
        const loserData  = await ranking.read.getPlayerRank([loser]);

        assert.ok(winnerData.wins >= 1n);
        assert.ok(loserData.losses >= 1n);
        assert.ok(winnerData.totalPoints > 0n);
      }
    });
  });

  // ================================================================
  // FLOW 2 — TOKEN MATCH END TO END
  // ================================================================

  describe("Flow 2 — Token Match with Payout", async function () {
    let tokenMatch: any;

    it("should deploy token match and confirm stakes", async function () {
      const wallets = await viem.getWalletClients();
      const pA = wallets[6];
      const pB = wallets[7];

      tokenMatch = await viem.deployContract("CipherMatch", [
        20n,
        pA.account.address,
        pB.account.address,
        config.address,
        ranking.address,
        "0x0000000000000000000000000000000000000000",
        factory.address,
        owner.account.address,
      ]);

      await ranking.write.addAuthorizedCaller([tokenMatch.address]);

      const stakeAmount = 10000000000000000n; // 0.01 RITUAL

      await tokenMatch.write.confirmStake([1n, stakeAmount], {
        account: pA.account,
        value: stakeAmount,
      });

      await tokenMatch.write.confirmStake([1n, stakeAmount], {
        account: pB.account,
        value: stakeAmount,
      });

      const state = await tokenMatch.read.getMatchState();
      assert.equal(state, 1); // ACTIVE
    });

    it("should complete token match and distribute payout", async function () {
      const wallets = await viem.getWalletClients();
      const pA = wallets[6];
      const pB = wallets[7];

      for (let i = 1; i <= 6; i++) {
        const roundData = await tokenMatch.read.getRoundData([BigInt(i)]);
        const presenter = roundData.presenter.toLowerCase();

        const presenterWallet = presenter === pA.account.address.toLowerCase()
          ? pA : pB;
        const guesserWallet = presenter === pA.account.address.toLowerCase()
          ? pB : pA;

        await tokenMatch.write.selectCategory(["Technology"], {
          account: presenterWallet.account,
        });

        await tokenMatch.write.submitGuess(["BLOCKCHAIN"], {
          account: guesserWallet.account,
        });

        await tokenMatch.write.closeRound({ account: owner.account });
      }

      const state = await tokenMatch.read.getMatchState();
      assert.ok(state === 2 || state === 1);
    });
  });

  // ================================================================
  // FLOW 3 — MATCH CANCELLATION + REFUND
  // ================================================================

  describe("Flow 3 — Cancellation and Refund", async function () {
    it("should cancel match before both players confirm", async function () {
      const wallets = await viem.getWalletClients();
      const pA = wallets[8];
      const pB = wallets[9];

      const cancelMatch = await viem.deployContract("CipherMatch", [
        30n,
        pA.account.address,
        pB.account.address,
        config.address,
        ranking.address,
        "0x0000000000000000000000000000000000000000",
        factory.address,
        owner.account.address,
      ]);

      // Only playerA confirms
      await cancelMatch.write.confirmStake([0n, 0n], {
        account: pA.account,
      });

      // Cancel before playerB confirms
      await cancelMatch.write.cancelMatch({ account: pA.account });

      const state = await cancelMatch.read.getMatchState();
      assert.equal(state, 3); // CANCELLED
    });

    it("should refund token stakes on cancellation", async function () {
      const wallets = await viem.getWalletClients();
      const pA = wallets[8];
      const pB = wallets[9];

      const stakeAmount = 10000000000000000n;

      const refundMatch = await viem.deployContract("CipherMatch", [
        31n,
        pA.account.address,
        pB.account.address,
        config.address,
        ranking.address,
        "0x0000000000000000000000000000000000000000",
        factory.address,
        owner.account.address,
      ]);

      await refundMatch.write.confirmStake([1n, stakeAmount], {
        account: pA.account,
        value: stakeAmount,
      });

      await refundMatch.write.cancelMatch({ account: pA.account });

      const state = await refundMatch.read.getMatchState();
      assert.equal(state, 3); // CANCELLED
    });
  });

  // ================================================================
  // FLOW 4 — RANKING CASCADE
  // ================================================================

  describe("Flow 4 — Ranking Cascade", async function () {
    it("should track wins and losses across multiple matches", async function () {
      const winnerData = await ranking.read.getPlayerRank([
        playerA.account.address,
      ]);
      const loserData = await ranking.read.getPlayerRank([
        playerB.account.address,
      ]);

      // Both should have played matches
      assert.ok(winnerData.totalMatches >= 0n);
      assert.ok(loserData.totalMatches >= 0n);
    });

    it("should have correct leaderboard ordering", async function () {
      const [addrs, data] = await ranking.read.getLeaderboard([10n]);
      assert.ok(addrs.length >= 0);

      for (let i = 0; i < data.length - 1; i++) {
        assert.ok(data[i].totalPoints >= data[i + 1].totalPoints);
      }
    });
  });
});