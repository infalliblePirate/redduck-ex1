// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SortedPriceList with off-chain sorting
/// @notice Maintains a doubly linked list of prices sorted by votes
/// @dev Requires off-chain computation to find correct insertion position
contract SortedPriceList {
    struct PriceNode {
        uint256 price;
        uint256 votes;
        uint256 next;
        uint256 prev;
    }

    uint256 private head;
    PriceNode[] private nodes;
    mapping(uint256 => uint256) private priceToIndex;

    event NodeUpserted(uint256 indexed price, uint256 votes, uint256 index);
    event NodeRemoved(uint256 indexed price, uint256 index);

    error InvalidPosition();
    error InvalidPrevNode();
    error NodeNotFound();

    constructor() {
        // null value node
        nodes.push(PriceNode(0, 0, 0, 0));
    }

    /// @notice Inserts or updates a price node using off-chain computed position
    /// @param price The price to insert or update
    /// @param votes Total votes for this price
    /// @param insertAfter Index of the node after which to insert (0 to insert at head)
    /// @dev Caller must compute correct insertAfter off-chain to maintain sort order
    function upsert(
        uint256 price,
        uint256 votes,
        uint256 insertAfter
    ) external {
        uint256 idx = priceToIndex[price];

        if (votes == 0) {
            _remove(price);
            return;
        }

        // update existing
        if (idx != 0) {
            _unlinkNode(idx);
            nodes[idx].votes = votes;
            _linkNode(idx, insertAfter);
            emit NodeUpserted(price, votes, idx);
            return;
        }

        // insert new
        idx = nodes.length;
        nodes.push(PriceNode(price, votes, 0, 0));
        priceToIndex[price] = idx;
        _linkNode(idx, insertAfter);

        emit NodeUpserted(price, votes, idx);
    }

    function _unlinkNode(uint256 idx) internal {
        uint256 prevNode = nodes[idx].prev;
        uint256 nextNode = nodes[idx].next;

        if (prevNode == 0) {
            head = nextNode;
        } else {
            nodes[prevNode].next = nextNode;
        }

        if (nextNode != 0) {
            nodes[nextNode].prev = prevNode;
        }

        nodes[idx].prev = 0;
        nodes[idx].next = 0;
    }

    /// @notice Inserts a node at the specified position
    /// @param idx The index of the node to insert
    /// @param insertAfter Index of the node after which to insert (0 for head)
    function _linkNode(uint256 idx, uint256 insertAfter) internal {
        uint256 nextIdx = nodes[idx].next;
        bool violatesOrder = (insertAfter != 0 &&
            nodes[insertAfter].votes < nodes[idx].votes) ||
            (nextIdx != 0 && nodes[idx].votes < nodes[nextIdx].votes);

        if (violatesOrder) revert InvalidPosition();

        // insert at head
        if (insertAfter == 0) {
            uint256 oldHead = head;

            nodes[idx].prev = 0;
            nodes[idx].next = oldHead;

            if (oldHead != 0) {
                nodes[oldHead].prev = idx;
            }

            head = idx;
            return;
        }

        // insert after an existing node
        uint256 nextAfterPrev = nodes[insertAfter].next;

        nodes[idx].prev = insertAfter;
        nodes[idx].next = nextAfterPrev;
        nodes[insertAfter].next = idx;

        if (nextAfterPrev != 0) {
            nodes[nextAfterPrev].prev = idx;
        }
    }

    /// @notice Removes a price node completely from the list
    /// @param price The price to remove
    function _remove(uint256 price) internal {
        uint256 idx = priceToIndex[price];
        if (idx == 0) revert NodeNotFound();

        _unlinkNode(idx);
        nodes[idx].price = 0;
        nodes[idx].votes = 0;

        delete priceToIndex[price];

        emit NodeRemoved(price, idx);
    }

    /// @notice Returns the price with the highest number of votes
    function getTopPrice() public view returns (uint256) {
        return nodes[head].price;
    }

    function getVotes(uint256 price) public view returns (uint256) {
        nodes[priceToIndex[price]].votes;
    }
}
