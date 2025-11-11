import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import hre from 'hardhat';

import { SortedPriceList__factory } from '../../typechain-types';

describe('SortedPriceList', function () {
  async function deployFixture() {
    const [deployer] = await hre.ethers.getSigners();
    const factory = new SortedPriceList__factory(deployer);
    const set = await factory.deploy();
    await set.waitForDeployment();
    return { deployer, set };
  }

  it('should upsert and keep elements sorted by votes', async function () {
    const { set } = await loadFixture(deployFixture);

    await set.upsert(10, 8);
    await set.upsert(20, 12);
    await set.upsert(5, 10);

    expect(await set.totalCount()).to.equal(3n);

    expect(await set.getTopPrice()).to.equal(20n);

    const nodes = await set.getSortedNodes();
    const prices = nodes.map((n) => n.price);
    const votes = nodes.map((n) => n.votes);

    expect(prices).to.deep.equal([20n, 5n, 10n]);
    expect(votes).to.deep.equal([12n, 10n, 8n]);
  });

  it('should replace an existing price with updated votes', async () => {
    const { set } = await loadFixture(deployFixture);

    await set.upsert(10, 5);
    await set.upsert(10, 15);

    const nodes = await set.getSortedNodes();
    expect(nodes.length).to.equal(1);
    expect(nodes[0].price).to.equal(10n);
    expect(nodes[0].votes).to.equal(15n);

    expect(await set.getTopPrice()).to.equal(10n);
    expect(await set.totalCount()).to.equal(1n);
  });

  // it('should remove a node correctly', async () => {
  //   const { set } = await loadFixture(deployFixture);

  //   await set.upsert(5, 10);
  //   await set.upsert(7, 15);
  //   await set.upsert(9, 5);

  //   expect(await set.totalCount()).to.equal(3n);
  //   expect(await set.getTopPrice()).to.equal(7n);

  //   await set._remove(7,2);
  //   expect(await set.totalCount()).to.equal(2n);

  //   expect(await set.getTopPrice()).to.equal(5n);

  //   await set._remove(9, 3);
  //   expect(await set.totalCount()).to.equal(1n);

  //   const remaining = await set.getSortedNodes();
  //   expect(remaining[0].price).to.equal(5n);
  //   expect(remaining[0].votes).to.equal(10n);
  // });

  it('should handle getVotes and found correctly', async () => {
    const { set } = await loadFixture(deployFixture);

    await set.upsert(100, 20);
    await set.upsert(200, 30);

    // const foundIdx = await set.found(200);
    // expect(foundIdx).to.not.equal(0n);

    expect(await set.getVotes(100)).to.equal(20n);
    expect(await set.getVotes(200)).to.equal(30n);
    expect(await set.getVotes(300)).to.equal(0n);
  });

  it('should return empty array when nothing upserted', async () => {
    const { set } = await loadFixture(deployFixture);

    expect(await set.totalCount()).to.equal(0n);
    expect(await set.getTopPrice()).to.equal(0n);

    const arr = await set.getSortedNodes();
    expect(arr.length).to.equal(0);
  });
});
