// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

pragma solidity ^0.8.9;

contract ERC20 is IERC20, IERC20Metadata {
    uint8 internal _decimals;
    uint256 internal _supply;
    string internal _name;
    string internal _symbol;

    mapping(address => uint256) internal _balanceOf;
    mapping(address => mapping(address => uint256)) internal _allowances;

    constructor(
        uint8 decimals,
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) {
        _decimals = decimals;
        _name = name;
        _symbol = symbol;
        uint256 supply = initialSupply * 10 ** decimals;
        _mint(address(this), supply);
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return _supply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "The sender is a zero address");
        require(spender != address(0), "The receipient is a zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        uint256 currAllowance = _allowances[from][msg.sender];
        require(
            currAllowance >= value,
            "The transferable value exceeds allowance"
        );
        _approve(from, msg.sender, currAllowance - value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "The sender is a zero address");
        require(to != address(0), "The receipient is a zero address");
        require(
            _balanceOf[from] >= value,
            "The transferable value exceeds balance"
        );
        _balanceOf[from] -= value;
        _balanceOf[to] += value;

        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "The receipient is a zero address");
        _balanceOf[to] += value;
        _supply += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        require(from != address(0), "The sender is a zero address");
        require(_balanceOf[from] >= value, "The burn amount exceeds balance");
        _balanceOf[from] -= value;
        _supply -= value;
        emit Transfer(from, address(0), value);
    }
}
