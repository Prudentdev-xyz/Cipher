import assert from "node:assert/strict";
import { describe, it, before } from "node:test";
import hre from "hardhat";

describe("CipherConfig", async function () {
  let viem: any;
  let config: any;
  let treasury: any;
  let otherUser: any;

  before(async function () {
    const network = await hre.network.create();
    viem = network.viem;

    const wallets = await viem.getWalletClients();
    treasury = wallets[1];
    otherUser = wallets[2];

    config = await viem.deployContract("CipherConfig", [
      treasury.account.address,
    ]);
  });

  it("should set correct defaults on deploy", async function () {
    assert.equal(await config.read.platformFeePercent(), 5n);
    assert.equal(await config.read.spectatorFeePercent(), 5n);
    assert.equal(await config.read.roundCount(), 6n);
    assert.equal(await config.read.roundDurationSeconds(), 30n);
    assert.equal(await config.read.getCategoryCount(), 20n);
  });

  it("should allow owner to update platform fee", async function () {
    await config.write.setPlatformFeePercent([10n]);
    assert.equal(await config.read.platformFeePercent(), 10n);
  });

  it("should reject fee above 20%", async function () {
    await assert.rejects(
      config.write.setPlatformFeePercent([21n])
    );
  });

  it("should reject non-owner calls", async function () {
    await assert.rejects(
      config.write.setPlatformFeePercent([10n], {
        account: otherUser.account,
      })
    );
  });

  it("should validate stake amounts correctly", async function () {
    assert.equal(await config.read.isValidStakeAmount([10000000000000000n]), true);
    assert.equal(await config.read.isValidStakeAmount([50000000000000000n]), true);
    assert.equal(await config.read.isValidStakeAmount([99999999999999999n]), false);
  });

  it("should validate categories correctly", async function () {
    assert.equal(await config.read.isCategoryValid(["Science"]), true);
    assert.equal(await config.read.isCategoryValid(["Web3 & Crypto"]), true);
    assert.equal(await config.read.isCategoryValid(["FakeCategory"]), false);
  });

  it("should allow owner to add a category", async function () {
    await config.write.addCategory(["Anime"]);
    assert.equal(await config.read.getCategoryCount(), 21n);
    assert.equal(await config.read.isCategoryValid(["Anime"]), true);
  });
});