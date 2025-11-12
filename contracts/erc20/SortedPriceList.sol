// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SortedPriceList
/// @author Kateryna Pavlenko
/// @notice Maintains a singly linked list of prices sorted by votes in descending order
contract SortedPriceList {
    /// @notice Represents a node in the sorted linked list
    /// @param price The price value
    /// @param votes The total votes associated with this price
    /// @param nextIndex The index of the next node in the linked list
    /// @param exists Whether the node is currently active
    struct PriceNode {
        uint256 price;
        uint256 votes;
        uint256 nextIndex;
        bool exists;
    }

    /// @notice Index of the head
    uint256 public headIndex;

    /// @dev Internal storage of all nodes; node index starts at 1 (0 is reserved)
    PriceNode[] private nodes;

    /// @notice Number of active nodes in the list
    /// @dev Used in tests to verify the number of existing entries
    uint256 public totalCount;

    /// @dev Maps price -> node index in the nodes array
    mapping(uint256 => uint256) private indexOf;

    /// @notice Initializes the contract and reserves the first node index (0)
    constructor() {
        nodes.push(PriceNode(0, 0, 0, false));
    }

    /**
     * @notice Updates an existing price or inserts a new one while maintaining sorted order
     * @param price The price value to insert or update
     * @param votes The total number of votes for the price
     */
    function upsert(uint256 price, uint256 votes) external {
        uint256 index = indexOf[price];
        if (index != 0 && nodes[index].exists) {
            update(price, votes);
        } else {
            insert(price, votes);
        }
    }

    /**
     * @notice Inserts a new price into the sorted linked list
     * @param price The price value to insert
     * @param votes The total votes for the price
     */
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

    /**
     * @notice Updates the vote count of an existing price
     * @dev Removes and reinserts the node to maintain correct sort order
     * @param price The price whose votes are updated
     * @param newVotes The new vote count for the price
     */
    function update(uint256 price, uint256 newVotes) internal {
        uint256 index = indexOf[price];
        if (index == 0 || !nodes[index].exists) revert("Node does not exist");

        uint256 oldVotes = nodes[index].votes;
        if (oldVotes == newVotes) return;

        _remove(price, index);
        insert(price, newVotes);
    }

    /**
     * @notice Creates and stores a new node in the list
     * @param price The price value
     * @param votes The total votes for the price
     * @return newIndex The index of the newly created node
     */
    function _createNode(
        uint256 price,
        uint256 votes
    ) internal returns (uint256 newIndex) {
        newIndex = nodes.length;
        nodes.push(PriceNode(price, votes, 0, true));
        indexOf[price] = newIndex;
    }

    /**
     * @notice Removes a node from the list
     * @param price The price value corresponding to the node
     * @param index The index of the node to remove
     */
    function _remove(uint256 price, uint256 index) internal {
        nodes[index].exists = false;
        delete indexOf[price];
        unchecked {
            --totalCount;
        }

        if (headIndex == index) {
            uint256 current = nodes[index].nextIndex;
            while (current != 0 && !nodes[current].exists) {
                current = nodes[current].nextIndex;
            }
            headIndex = current;
        }
    }

    /**
     * @notice Returns the price with the highest number of votes
     * @return The top (most voted) price
     */
    function getTopPrice() public view returns (uint256) {
        return nodes[headIndex].price;
    }

    /**
     * @notice Retrieves the vote count for a given price
     * @param price The price to look up
     * @return The total votes for the price, or 0 if the price does not exist
     */
    function getVotes(uint256 price) public view returns (uint256) {
        uint256 index = indexOf[price];
        if (index == 0 || !nodes[index].exists) return 0;
        return nodes[index].votes;
    }

    /**
     * @notice Returns all nodes in descending vote order
     * @dev Used primarily for testing or off-chain inspection
     * @return An array of all active PriceNodes in sorted order
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
