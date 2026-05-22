import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import hre from "hardhat";

describe("CipherMatchFactory", async function () {
  let viem: any;
  let factory: any;
  let config: any;
  let ranking: any;
  let owner: any;
  let playerA: any;
  let playerB: any;
  let playerC: any;

  before(async function () {
    const network = await hre.network.create();
    viem = network.viem;

    const wallets = await viem.getWalletClients();
    owner = wallets[0];
    playerA = wallets[1];
    playerB = wallets[2];
    playerC = wallets[3];

    config = await viem.deployContract("CipherConfig", [
      owner.account.address,
    ]);

    ranking = await viem.deployContract("CipherRanking", [
      config.address,
    ]);

    factory = await viem.deployContract("CipherMatchFactory", [
      config.address,
      ranking.address,
      owner.account.address, // spectator placeholder
    ]);
  });

  it("should store first player as pending", async function () {
    await factory.write.joinMatch(["TESTCODE1"], {
      account: playerA.account,
    });

    const [addr] = await factory.read.getPendingPlayer(["TESTCODE1"]);
    assert.equal(addr.toLowerCase(), playerA.account.address.toLowerCase());
  });

  it("should mark player as in pending", async function () {
    const inPending = await factory.read.isPlayerInPending([
      playerA.account.address,
    ]);
    assert.equal(inPending, true);
  });

  it("should pair two players and create a match", async function () {
    await factory.write.joinMatch(["TESTCODE1"], {
      account: playerB.account,
    });

    const matchCount = await factory.read.getTotalMatchCount();
    assert.equal(matchCount, 1n);
  });

  it("should record match in player history", async function () {
    const matchesA = await factory.read.getPlayerMatches([
      playerA.account.address,
    ]);
    const matchesB = await factory.read.getPlayerMatches([
      playerB.account.address,
    ]);
    assert.equal(matchesA.length, 1);
    assert.equal(matchesB.length, 1);
  });

  it("should reject same player joining twice", async function () {
    await factory.write.joinMatch(["TESTCODE2"], {
      account: playerC.account,
    });

    await assert.rejects(
      factory.write.joinMatch(["TESTCODE3"], {
        account: playerC.account,
      })
    );
  });

  it("should allow player to cancel pending", async function () {
    const wallets = await viem.getWalletClients();
    const playerD = wallets[4];

    await factory.write.joinMatch(["TESTCODE4"], {
      account: playerD.account,
    });

    await factory.write.cancelPending(["TESTCODE4"], {
      account: playerD.account,
    });

    const inPending = await factory.read.isPlayerInPending([
      playerD.account.address,
    ]);
    assert.equal(inPending, false);
  });

  it("should reject cancelling another player pending slot", async function () {
    const wallets = await viem.getWalletClients();
    const playerE = wallets[5];
    const playerF = wallets[6];

    await factory.write.joinMatch(["TESTCODE5"], {
      account: playerE.account,
    });

    await assert.rejects(
      factory.write.cancelPending(["TESTCODE5"], {
        account: playerF.account,
      })
    );
  });
});