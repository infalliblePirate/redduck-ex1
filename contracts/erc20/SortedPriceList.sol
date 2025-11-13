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

    event NodeInserted(uint256 indexed price, uint256 votes, uint256 index);
    event NodeUpdated(uint256 indexed price, uint256 votes, uint256 index);
    event NodeRemoved(uint256 indexed price, uint256 index);

    error InvalidPosition();
    error NodeNotFound();
    error NodeAlreadyExists();

    constructor() {
        // null value node
        nodes.push(PriceNode(0, 0, 0, 0));
    }

    /// @notice Insert a new price node
    function insert(
        uint256 price,
        uint256 votes,
        uint256 insertAfter
    ) external {
        if (priceToIndex[price] != 0) revert NodeAlreadyExists();

        uint256 idx = nodes.length;
        nodes.push(PriceNode(price, votes, 0, 0));
        priceToIndex[price] = idx;
        _linkNode(idx, insertAfter);

        emit NodeInserted(price, votes, idx);
    }

    /// @notice Update an existing node's votes and reposition it
    function update(
        uint256 price,
        uint256 votes,
        uint256 insertAfter
    ) external {
        uint256 idx = priceToIndex[price];
        if (idx == 0) revert NodeNotFound();

        _unlinkNode(idx);
        nodes[idx].votes = votes;
        _linkNode(idx, insertAfter);

        emit NodeUpdated(price, votes, idx);
    }

    /// @notice Remove a node
    function remove(uint256 price) external {
        uint256 idx = priceToIndex[price];
        if (idx == 0) revert NodeNotFound();

        _unlinkNode(idx);
        nodes[idx].price = 0;
        nodes[idx].votes = 0;
        delete priceToIndex[price];

        emit NodeRemoved(price, idx);
    }

    /// @notice Returns the price with the highest votes
    function getTopPrice() public view returns (uint256) {
        return nodes[head].price;
    }

    /// @notice Returns the votes of a price
    function getVotes(uint256 price) public view returns (uint256) {
        uint256 idx = priceToIndex[price];
        return nodes[idx].votes;
    }

    /// @notice Unlink a node from the list
    function _unlinkNode(uint256 idx) internal {
        uint256 prevNode = nodes[idx].prev;
        uint256 nextNode = nodes[idx].next;

        if (prevNode == 0) head = nextNode;
        else nodes[prevNode].next = nextNode;

        if (nextNode != 0) nodes[nextNode].prev = prevNode;

        nodes[idx].prev = 0;
        nodes[idx].next = 0;
    }

    /// @notice Link a node after another node
    function _linkNode(uint256 idx, uint256 insertAfter) internal {
        uint256 nextIdx = nodes[idx].next;

        bool violatesOrder = (insertAfter != 0 &&
            nodes[insertAfter].votes < nodes[idx].votes) ||
            (nextIdx != 0 && nodes[idx].votes < nodes[nextIdx].votes);

        if (violatesOrder) revert InvalidPosition();

        if (insertAfter == 0) {
            uint256 oldHead = head;
            nodes[idx].prev = 0;
            nodes[idx].next = oldHead;

            if (oldHead != 0) nodes[oldHead].prev = idx;
            head = idx;
            return;
        }

        uint256 nextAfterPrev = nodes[insertAfter].next;
        nodes[idx].prev = insertAfter;
        nodes[idx].next = nextAfterPrev;
        nodes[insertAfter].next = idx;

        if (nextAfterPrev != 0) nodes[nextAfterPrev].prev = idx;
    }
}
