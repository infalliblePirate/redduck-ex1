// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
     * @notice Updates existing price or inserts a new one.
     * @param price The price user votes for
     * @param votes The total votes for that price
     */
    function upsert(uint256 price, uint256 votes) external {
        uint256 index = indexOf[price];
        if (index != 0 && nodes[index].exists) {
            update(price, votes);
        } else {
            insert(price, votes);
        }
    }

    function insert(uint256 price, uint256 votes) internal {
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

    function update(uint256 price, uint256 newVotes) internal {
        uint256 index = indexOf[price];
        if (index == 0 || !nodes[index].exists) revert("Node does not exist");

        uint256 oldVotes = nodes[index].votes;

        if (oldVotes == newVotes) return;

        _remove(price, index);
        insert(price, newVotes);
    }

    function _createNode(
        uint256 price,
        uint256 votes
    ) internal returns (uint256) {
        uint256 newIndex = nodes.length;
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
        } else {
            uint256 prev = _findPrevious(index);
            if (prev != 0) {
                nodes[prev].nextIndex = nodes[index].nextIndex;
            }
        }

        nodes[index].exists = false;
        delete indexOf[price];
        unchecked {
            --totalCount;
        }
    }

    function _findPrevious(uint256 index) internal view returns (uint256) {
        uint256 current = headIndex;
        while (current != 0) {
            if (nodes[current].nextIndex == index) {
                return current;
            }
            current = nodes[current].nextIndex;
        }
        return 0;
    }

    function getTopPrice() public view returns (uint256) {
        return nodes[headIndex].price;
    }

    function getVotes(uint256 price) public view returns (uint256) {
        uint256 index = indexOf[price];
        if (index == 0 || !nodes[index].exists) return 0;
        return nodes[index].votes;
    }

    /**
     * @notice Returns all nodes in sorted order
     * @dev For testing only
     */
    function getSortedNodes() public view returns (PriceNode[] memory) {
        PriceNode[] memory sortedNodes = new PriceNode[](totalCount);

        uint256 current = headIndex;
        uint256 i;
        while (current != 0) {
            if (nodes[current].exists) {
                sortedNodes[i++] = nodes[current];
            }
            current = nodes[current].nextIndex;
        }

        return sortedNodes;
    }
}
