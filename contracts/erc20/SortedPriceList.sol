// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SortedPriceList {
    struct PriceNode {
        uint256 price;
        uint256 votes;
        uint256 nextIndex;
    }

    uint256 public headIndex;
    PriceNode[] private nodes;
    uint256 public totalCount;

    uint256 private constant NULL_INDEX = type(uint256).max;

    constructor() {
        headIndex = NULL_INDEX;
    }

    /**
     * @notice Updates the existing price or inserts new
     * @param price The price user votes for
     * @param votes The total amount of votes of the price
     */
    function upsert(uint256 price, uint256 votes) public {
        _removeIfExists(price);

        nodes.push(PriceNode(price, votes, NULL_INDEX));
        uint256 newIndex = nodes.length - 1;

        if (headIndex == NULL_INDEX) {
            headIndex = newIndex;
            totalCount++;
            return;
        }

        if (nodes[headIndex].votes < votes) {
            nodes[newIndex].nextIndex = headIndex;
            headIndex = newIndex;
            totalCount++;
            return;
        }

        uint256 current = headIndex;
        while (nodes[current].nextIndex != NULL_INDEX) {
            uint256 next = nodes[current].nextIndex;
            if (nodes[next].votes < votes) {
                nodes[current].nextIndex = newIndex;
                nodes[newIndex].nextIndex = next;
                totalCount++;
                return;
            }
            current = next;
        }

        nodes[current].nextIndex = newIndex;
        totalCount++;
    }

    function getTopPrice() public view returns (uint256) {
        if (headIndex == NULL_INDEX) return 0;
        return nodes[headIndex].price;
    }

    function findIndexByPrice(uint256 price) public view returns (uint256) {
        uint256 current = headIndex;
        while (current != NULL_INDEX) {
            if (nodes[current].price == price) {
                return current;
            }
            current = nodes[current].nextIndex;
        }
        return NULL_INDEX;
    }

    function getVotes(uint256 price) public view returns (uint256) {
        uint256 index = findIndexByPrice(price);
        if (index == NULL_INDEX) return 0;
        return nodes[index].votes;
    }

    function _removeIfExists(uint256 price) internal {
        uint256 current = headIndex;
        uint256 prev = NULL_INDEX;

        while (current != NULL_INDEX) {
            if (nodes[current].price == price) {
                if (prev == NULL_INDEX) {
                    headIndex = nodes[headIndex].nextIndex;
                } else {
                    nodes[prev].nextIndex = nodes[current].nextIndex;
                }
                delete nodes[current];
                totalCount--;
                return;
            }
            prev = current;
            current = nodes[current].nextIndex;
        }
    }

    /**
     * @notice Returns all nodes in sorted order
     */
    function getSortedNodes() public view returns (PriceNode[] memory) {
        PriceNode[] memory sortedNodes = new PriceNode[](totalCount);

        uint256 current = headIndex;
        for (uint256 i = 0; i < totalCount; i++) {
            sortedNodes[i] = nodes[current];
            current = nodes[current].nextIndex;
        }

        return sortedNodes;
    }
}
