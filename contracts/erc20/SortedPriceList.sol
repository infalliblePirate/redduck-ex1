// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// todo: ask about storage layout, do we take it into accout packing
contract SortedPriceList {
    struct PriceNode {
        uint256 price;
        uint256 votes;
        uint256 nextIndex;
        bool exists;
    }

    uint256 public headIndex;
    PriceNode[] private nodes;
    uint256 public totalCount;

    mapping(uint256 => uint256) private indexOf; // price -> index

    constructor() {
        nodes.push(PriceNode(0, 0, 0, false));
    }

    /**
     * @notice Updates the existing price or inserts new
     * @param price The price user votes for
     * @param votes The total amount of votes of the price
     */
    function upsert(uint256 price, uint256 votes) external {
        uint256 index = indexOf[price];
        if (index != 0 && nodes[index].exists) {
            _remove(price, index);
        }

        uint256 newIndex = _createNode(price, votes);

        if (headIndex == 0) {
            headIndex = newIndex;
            unchecked {
                ++totalCount;
            }
            return;
        }

        if (nodes[headIndex].votes < votes) {
            nodes[newIndex].nextIndex = headIndex;
            headIndex = newIndex;
            unchecked {
                ++totalCount;
            }
            return;
        }

        uint256 current = headIndex;
        while (true) {
            uint256 next = nodes[current].nextIndex;

            if (next == 0) {
                nodes[current].nextIndex = newIndex;
                unchecked {
                    ++totalCount;
                }
                return;
            }

            if (!nodes[next].exists) {
                current = next;
                continue;
            }

            if (nodes[next].votes < votes) {
                nodes[current].nextIndex = newIndex;
                nodes[newIndex].nextIndex = next;
                unchecked {
                    ++totalCount;
                }
                return;
            }

            current = next;
        }
    }

    function _createNode(
        uint256 price,
        uint256 votes
    ) internal returns (uint256) {
        uint256 newIndex = uint256(nodes.length);
        nodes.push(PriceNode(price, votes, 0, true));
        indexOf[price] = newIndex;
        return newIndex;
    }

    function _remove(uint256 price, uint256 index) internal {
        if (headIndex == index) {
            uint256 current = nodes[index].nextIndex;
            while (current != 0 && !nodes[current].exists) {
                current = nodes[current].nextIndex;
            }
            headIndex = current;
        }

        nodes[index].exists = false;
        delete indexOf[price];
        unchecked {
            --totalCount;
        }
    }

    function getTopPrice() public view returns (uint256) {
        return nodes[headIndex].price;
    }

    function getVotes(uint256 price) public view returns (uint256) {
        uint256 index = indexOf[price];
        if (!nodes[index].exists) return 0;
        return nodes[index].votes;
    }

    /**
     * @notice Returns all nodes in sorted order
     * @notice Use only in tests
     */
    function getSortedNodes() public view returns (PriceNode[] memory) {
        PriceNode[] memory sortedNodes = new PriceNode[](totalCount);

        uint256 current = headIndex;
        for (uint256 i = 0; i < totalCount; i++) {
            if (!nodes[current].exists) continue;
            sortedNodes[i] = nodes[current];
            current = nodes[current].nextIndex;
        }

        return sortedNodes;
    }
}
