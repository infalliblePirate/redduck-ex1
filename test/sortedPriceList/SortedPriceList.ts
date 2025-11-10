import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import hre from 'hardhat';

import { SortedArraySet__factory } from '../../typechain-types';

describe('SortedArraySet', function () {
  async function deployFixture() {
    const [deployer] = await hre.ethers.getSigners();
    const factory = new SortedArraySet__factory(deployer);
    const set = await factory.deploy();
    await set.waitForDeployment();
    return { deployer, set };
  }

  it('should insert and keep elements sorted by votes', async function () {
    const { set } = await loadFixture(deployFixture);

    await set.insert(10, 8);
    await set.insert(20, 12);
    await set.insert(5, 10);

    expect(await set.size()).to.equal(3n);

    expect(await set.getWinningPrice()).to.equal(20n);

    const nodes = await set.getPrices();
    const prices = nodes.map((n) => n.price);
    const votes = nodes.map((n) => n.votes);

    expect(prices).to.deep.equal([20n, 5n, 10n]);
    expect(votes).to.deep.equal([12n, 10n, 8n]);
  });

  it('should replace an existing price with updated votes', async () => {
    const { set } = await loadFixture(deployFixture);

    await set.insert(10, 5);
    await set.insert(10, 15);

    const nodes = await set.getPrices();
    expect(nodes.length).to.equal(1);
    expect(nodes[0].price).to.equal(10n);
    expect(nodes[0].votes).to.equal(15n);

    expect(await set.getWinningPrice()).to.equal(10n);
    expect(await set.size()).to.equal(1n);
  });

  it('should remove a node correctly', async () => {
    const { set } = await loadFixture(deployFixture);

    await set.insert(5, 10);
    await set.insert(7, 15);
    await set.insert(9, 5);

    expect(await set.size()).to.equal(3n);
    expect(await set.getWinningPrice()).to.equal(7n);

    await set.removeIfExists(7);
    expect(await set.size()).to.equal(2n);

    expect(await set.getWinningPrice()).to.equal(5n);

    await set.removeIfExists(9);
    expect(await set.size()).to.equal(1n);

    const remaining = await set.getPrices();
    expect(remaining[0].price).to.equal(5n);
    expect(remaining[0].votes).to.equal(10n);
  });

  it('should handle getVotes and found correctly', async () => {
    const { set } = await loadFixture(deployFixture);

    await set.insert(100, 20);
    await set.insert(200, 30);

    const foundIdx = await set.found(200);
    expect(foundIdx).to.not.equal(0n);

    expect(await set.getVotes(100)).to.equal(20n);
    expect(await set.getVotes(200)).to.equal(30n);
    expect(await set.getVotes(300)).to.equal(0n);
  });

  it('should return empty array when nothing inserted', async () => {
    const { set } = await loadFixture(deployFixture);

    expect(await set.size()).to.equal(0n);
    expect(await set.getWinningPrice()).to.equal(0n);

    const arr = await set.getPrices();
    expect(arr.length).to.equal(0);
  });
});
