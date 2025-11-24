import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import hre from 'hardhat';

import { SortedPriceList__factory } from '../../typechain-types';

describe('SortedPriceList', function () {
  async function deployFixture() {
    const [deployer] = await hre.ethers.getSigners();
    const factory = new SortedPriceList__factory(deployer);
    const list = await factory.deploy();
    await list.waitForDeployment();
    return { deployer, list };
  }

  describe('Insert', () => {
    it('should insert elements and keep them sorted by votes in descending order', async function () {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 8, 0, 0);
      await list.insert(20, 12, 0, 0);
      await list.insert(5, 10, 0, 0);

      expect(await list.size()).to.equal(3n);
      expect(await list.getTopPrice()).to.equal(20n);

      const prices: bigint[] = [];
      const votes: bigint[] = [];

      let current = await list.head();
      while (current !== 0n) {
        prices.push(current);
        votes.push(await list.getVotes(current));
        const [, next] = await list.getNode(current);
        current = next;
      }

      expect(prices).to.deep.equal([20n, 5n, 10n]);
      expect(votes).to.deep.equal([12n, 10n, 8n]);
    });

    it('should revert when inserting a price that already exists', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);

      await expect(list.insert(10, 15, 0, 0)).to.be.revertedWithCustomError(
        list,
        'NodeExists',
      );
    });

    it('should insert at head when votes are highest', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);
      await list.insert(20, 10, 0, 0);

      expect(await list.head()).to.equal(20n);
      expect(await list.getTopPrice()).to.equal(20n);
    });

    it('should insert at tail when votes are lowest', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      expect(await list.tail()).to.equal(20n);
      expect(await list.head()).to.equal(10n);
    });

    it('should handle inserting with hints', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      const [prev, next] = await list.findInsertPosition(7, 0, 0);
      await list.insert(15, 7, prev, next);

      expect(await list.size()).to.equal(3n);

      let current = await list.head();
      expect(current).to.equal(10n);

      [, current] = await list.getNode(current);
      expect(current).to.equal(15n);

      [, current] = await list.getNode(current);
      expect(current).to.equal(20n);
    });
  });

  describe('Update', () => {
    it('should update an existing node with new votes and reposition it', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);
      await list.insert(20, 10, 0, 0);
      await list.insert(30, 3, 0, 0);

      const [prev, next] = await list.findInsertPosition(15, 0, 0);
      await list.update(10, 15, prev, next);

      expect(await list.getTopPrice()).to.equal(10n);
      expect(await list.getVotes(10)).to.equal(15n);
      expect(await list.size()).to.equal(3n);

      const prices: bigint[] = [];
      let current = await list.head();
      while (current !== 0n) {
        prices.push(current);
        const [, next] = await list.getNode(current);
        current = next;
      }
      expect(prices).to.deep.equal([10n, 20n, 30n]);
    });

    it('should revert when updating a non-existent node', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);

      await expect(list.update(20, 15, 0, 0)).to.be.revertedWithCustomError(
        list,
        'NodeNotFound',
      );
    });
  });

  describe('Remove', () => {
    it('should remove a node correctly', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(5, 10, 0, 0);
      await list.insert(7, 15, 0, 0);
      await list.insert(9, 5, 0, 0);

      expect(await list.size()).to.equal(3n);
      expect(await list.getTopPrice()).to.equal(7n);

      await list.remove(7);
      expect(await list.size()).to.equal(2n);
      expect(await list.getTopPrice()).to.equal(5n);

      await list.remove(9);
      expect(await list.size()).to.equal(1n);

      expect(await list.head()).to.equal(5n);
      expect(await list.tail()).to.equal(5n);
      expect(await list.getVotes(5)).to.equal(10n);
    });

    it('should revert when removing a non-existent node', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);

      await expect(list.remove(20)).to.be.revertedWithCustomError(
        list,
        'NodeNotFound',
      );
    });

    it('should handle removing head', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      await list.remove(10);

      expect(await list.head()).to.equal(20n);
      expect(await list.tail()).to.equal(20n);
      expect(await list.size()).to.equal(1n);
    });

    it('should handle removing tail', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      await list.remove(20);

      expect(await list.head()).to.equal(10n);
      expect(await list.tail()).to.equal(10n);
      expect(await list.size()).to.equal(1n);
    });

    it('should handle removing all nodes', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);
      await list.remove(10);

      expect(await list.size()).to.equal(0n);
      expect(await list.head()).to.equal(0n);
      expect(await list.tail()).to.equal(0n);
    });
  });

  describe('View functions', () => {
    it('should handle getVotes and contains correctly', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(100, 20, 0, 0);
      await list.insert(200, 30, 0, 0);

      await expect(list.contains(100)).to.eventually.be.true;
      await expect(list.contains(200)).to.eventually.be.true;
      await expect(list.contains(300)).to.eventually.be.false;

      expect(await list.getVotes(100)).to.equal(20n);
      expect(await list.getVotes(200)).to.equal(30n);
      expect(await list.getVotes(300)).to.equal(0n);
    });

    it('should return correct isEmpty state', async () => {
      const { list } = await loadFixture(deployFixture);

      await expect(list.isEmpty()).to.eventually.be.true;
      expect(await list.size()).to.equal(0n);
      expect(await list.getTopPrice()).to.equal(0n);

      await list.insert(10, 5, 0, 0);
      await expect(list.isEmpty()).to.eventually.be.false;

      await list.remove(10);
      await expect(list.isEmpty()).to.eventually.be.true;
    });

    it('should return correct node structure', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      const [prev1, next1] = await list.getNode(10);
      expect(prev1).to.equal(0n);
      expect(next1).to.equal(20n);

      const [prev2, next2] = await list.getNode(20);
      expect(prev2).to.equal(10n);
      expect(next2).to.equal(0n);
    });
  });

  describe('findInsertPosition', () => {
    it('should find correct position for insertion', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(30, 5, 0, 0);

      const [prev, next] = await list.findInsertPosition(7, 0, 0);
      expect(prev).to.equal(10n);
      expect(next).to.equal(30n);
    });

    it('should find position at head for highest votes', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      const [prev, next] = await list.findInsertPosition(15, 0, 0);
      expect(prev).to.equal(0n);
      expect(next).to.equal(10n);
    });

    it('should find position at tail for lowest votes', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 5, 0, 0);

      const [prev, next] = await list.findInsertPosition(3, 0, 0);
      expect(prev).to.equal(20n);
      expect(next).to.equal(0n);
    });

    it('should use hints when provided', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 8, 0, 0);
      await list.insert(30, 6, 0, 0);

      const [prev, next] = await list.findInsertPosition(7, 10, 0);
      expect(prev).to.equal(20n);
      expect(next).to.equal(30n);
    });
  });

  describe('Complex scenarios', () => {
    it('should maintain sorted order through multiple operations', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 5, 0, 0);
      await list.insert(20, 15, 0, 0);
      await list.insert(30, 10, 0, 0);
      await list.insert(40, 3, 0, 0);

      const [prev1, next1] = await list.findInsertPosition(20, 0, 0);
      await list.update(10, 20, prev1, next1);

      await list.remove(30);

      const prices: bigint[] = [];
      const votes: bigint[] = [];

      let current = await list.head();
      while (current !== 0n) {
        prices.push(current);
        votes.push(await list.getVotes(current));
        const [, next] = await list.getNode(current);
        current = next;
      }

      expect(prices).to.deep.equal([10n, 20n, 40n]);
      expect(votes).to.deep.equal([20n, 15n, 3n]);

      for (let i = 1; i < votes.length; i++) {
        expect(votes[i - 1]).to.be.gte(votes[i]);
      }
    });

    it('should handle equal vote counts', async () => {
      const { list } = await loadFixture(deployFixture);

      await list.insert(10, 10, 0, 0);
      await list.insert(20, 10, 0, 0);
      await list.insert(30, 10, 0, 0);

      expect(await list.size()).to.equal(3n);

      const votes1 = await list.getVotes(10);
      const votes2 = await list.getVotes(20);
      const votes3 = await list.getVotes(30);

      expect(votes1).to.equal(10n);
      expect(votes2).to.equal(10n);
      expect(votes3).to.equal(10n);
    });
  });
});
