// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SortedPriceList {
    struct PriceNode {
        uint256 price;
        uint256 votes;
        uint256 prev;
        uint256 next;
    }

    mapping(uint256 => PriceNode) public nodes;

    uint256 public head;
    uint256 public tail;
    uint256 public size;

    error NodeExists();
    error NodeNotFound();
    error InvalidPosition();

    function contains(uint256 price) public view returns (bool) {
        return nodes[price].votes != 0;
    }

    function isEmpty() public view returns (bool) {
        return size == 0;
    }

    function getVotes(uint256 price) public view returns (uint256) {
        return nodes[price].votes;
    }

    function getTopPrice() public view returns (uint256) {
        return head;
    }

    function insert(
        uint256 price,
        uint256 votes,
        uint256 prevHint,
        uint256 nextHint
    ) external {
        if (contains(price)) revert NodeExists();
        require(votes > 0);

        (prevHint, nextHint) = findInsertPosition(votes, prevHint, nextHint);

        _link(price, votes, prevHint, nextHint);
        size++;
    }

    function update(
        uint256 price,
        uint256 votes,
        uint256 prevHint,
        uint256 nextHint
    ) external {
        if (!contains(price)) revert NodeNotFound();

        _unlink(price);
        (prevHint, nextHint) = findInsertPosition(votes, prevHint, nextHint);
        _link(price, votes, prevHint, nextHint);
    }

    function remove(uint256 price) public {
        if (!contains(price)) revert NodeNotFound();
        _unlink(price);
        delete nodes[price];
        size--;
    }

    function findInsertPosition(
        uint256 votes,
        uint256 prevHint,
        uint256 nextHint
    ) public view returns (uint256 prevPrice, uint256 nextPrice) {
        bool prevValid = (prevHint == 0) || contains(prevHint);
        bool nextValid = (nextHint == 0) || contains(nextHint);

        if (!prevValid && !nextValid) {
            return _findFromHead(votes);
        }

        if (prevValid && !nextValid) {
            if (prevHint == 0) {
                return _findFromHead(votes);
            }
            return _descendList(votes, prevHint);
        }

        if (!prevValid && nextValid) {
            if (nextHint == 0) {
                return _findFromHead(votes);
            }
            return _ascendList(votes, nextHint);
        }

        if (_validInsertBetween(prevHint, nextHint, votes)) {
            return (prevHint, nextHint);
        }

        if (prevHint != 0 && nodes[prevHint].votes >= votes) {
            return _descendList(votes, prevHint);
        }

        if (nextHint != 0 && nodes[nextHint].votes <= votes) {
            return _ascendList(votes, nextHint);
        }

        return _findFromHead(votes);
    }

    function _descendList(
        uint256 votes,
        uint256 start
    ) internal view returns (uint256 prev, uint256 next) {
        prev = start;
        next = nodes[start].next;

        while (next != 0 && nodes[next].votes >= votes) {
            prev = next;
            next = nodes[next].next;
        }
    }

    function _ascendList(
        uint256 votes,
        uint256 start
    ) internal view returns (uint256 prev, uint256 next) {
        next = start;
        prev = nodes[start].prev;

        while (prev != 0 && nodes[prev].votes < votes) {
            next = prev;
            prev = nodes[prev].prev;
        }
    }

    function _findFromHead(
        uint256 votes
    ) internal view returns (uint256 prev, uint256 next) {
        next = head;
        prev = 0;
        while (next != 0 && nodes[next].votes >= votes) {
            prev = next;
            next = nodes[next].next;
        }
    }

    function _validInsertBetween(
        uint256 prevPrice,
        uint256 nextPrice,
        uint256 votes
    ) internal view returns (bool) {
        if (prevPrice == 0)
            return head == nextPrice && votes >= nodes[nextPrice].votes;
        if (nextPrice == 0)
            return tail == prevPrice && votes <= nodes[prevPrice].votes;

        return
            nodes[prevPrice].next == nextPrice &&
            nodes[prevPrice].votes >= votes &&
            nodes[nextPrice].votes <= votes;
    }

    function _link(
        uint256 price,
        uint256 votes,
        uint256 prevPrice,
        uint256 nextPrice
    ) internal {
        nodes[price] = PriceNode(price, votes, prevPrice, nextPrice);

        if (prevPrice == 0) head = price;
        else nodes[prevPrice].next = price;

        if (nextPrice == 0) tail = price;
        else nodes[nextPrice].prev = price;
    }

    function _unlink(uint256 price) internal {
        PriceNode storage n = nodes[price];

        if (n.prev == 0) head = n.next;
        else nodes[n.prev].next = n.next;

        if (n.next == 0) tail = n.prev;
        else nodes[n.next].prev = n.prev;
    }

    function getNode(
        uint256 price
    ) public view returns (uint256 prev, uint256 next) {
        prev = nodes[price].prev;
        next = nodes[price].next;
    }
}
