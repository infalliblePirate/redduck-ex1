// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title ERC20
 * @notice Custom ERC20 token implementation with minting and burning capabilities
 * @author Kateryna Pavlenko 
 */
contract ERC20 is IERC20, IERC20Metadata, Ownable {
    /// @notice Number of decimal places for token amounts
    /// @dev Immutable to save gas on repeated calls
    uint8 internal immutable _DECIMALS;

    /// @notice Total token supply in circulation
    uint256 internal _supply;

    /// @notice Human-readable name of the token
    string internal _name;

    /// @notice Short symbol/ticker for the token
    string internal _symbol;

    /// @notice Mapping of addresses to their token balances
    mapping(address => uint256) internal _balanceOf;

    /// @notice Nested mapping of token allowances (owner => spender => amount)
    mapping(address => mapping(address => uint256)) internal _allowances;

    /// @notice Address authorized to mint and burn tokens
    /// @dev Typically set to the exchange contract address
    address internal _minter;

    /**
     * @notice Restricts function access to the designated minter address
     * @dev Reverts if caller is not the minter
     */
    modifier onlyMinter() {
        require(msg.sender == _minter, "Not authorized");
        _;
    }

    /**
     * @notice Creates a new ERC20 token
     * @param decimals_ Number of decimal places (e.g., 18 for wei-like precision)
     * @param name_ Full name of the token
     * @param symbol_ Short symbol for the token
     */
    constructor(
        uint8 decimals_,
        string memory name_,
        string memory symbol_
    ) Ownable(msg.sender) {
        _DECIMALS = decimals_;
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC20Metadata
    function name() external view override returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20Metadata
    function decimals() external view override returns (uint8) {
        return _DECIMALS;
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return _supply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Sets the address authorized to mint and burn tokens
     * @dev Only callable by contract owner
     * @param minter Address to authorize (typically the exchange contract)
     */
    function setMinter(address minter) external onlyOwner {
        require(minter != address(0), "Minter cannot be zero address");
        _minter = minter;
    }

    /**
     * @notice Mints new tokens to a specified address
     * @dev Only callable by the designated minter
     * @param to Address to receive the newly minted tokens
     * @param value Amount of tokens to mint
     */
    function mint(address to, uint256 value) external onlyMinter {
        _mint(to, value);
    }

    /**
     * @notice Burns tokens from a specified address
     * @dev Only callable by the designated minter
     * @param from Address to burn tokens from
     * @param value Amount of tokens to burn
     */
    function burn(address from, uint256 value) external onlyMinter {
        _burn(from, value);
    }

    /**
     * @notice Internal function to approve spending allowance
     * @dev Updates allowance mapping and emits Approval event
     * @param owner Address of the token owner
     * @param spender Address authorized to spend tokens
     * @param value Amount of tokens approved for spending
     */
    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "The sender is a zero address");
        require(spender != address(0), "The recipient is a zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @inheritdoc IERC20
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

    /**
     * @notice Internal function to transfer tokens between addresses
     * @dev Updates balances and emits Transfer event
     * @param from Address sending the tokens
     * @param to Address receiving the tokens
     * @param value Amount of tokens to transfer
     */
    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "The sender is a zero address");
        require(to != address(0), "The recipient is a zero address");
        require(
            _balanceOf[from] >= value,
            "The transferable value exceeds balance"
        );
        _balanceOf[from] -= value;
        _balanceOf[to] += value;

        emit Transfer(from, to, value);
    }

    /**
     * @notice Internal function to create new tokens
     * @dev Increases recipient balance and total supply, emits Transfer from zero address
     * @param to Address to receive the minted tokens
     * @param value Amount of tokens to mint
     */
    function _mint(address to, uint256 value) internal {
        require(to != address(0), "The recipient is a zero address");
        require(value > 0, "Mint amount must be greater than 0");
        _balanceOf[to] += value;
        _supply += value;
        emit Transfer(address(0), to, value);
    }

    /**
     * @notice Internal function to destroy tokens
     * @dev Decreases holder balance and total supply, emits Transfer to zero address
     * @param from Address to burn tokens from
     * @param value Amount of tokens to burn
     */
    function _burn(address from, uint256 value) internal {
        require(from != address(0), "The sender is a zero address");
        require(value > 0, "Burn amount must be greater than 0");
        require(_balanceOf[from] >= value, "The burn amount exceeds balance");
        _balanceOf[from] -= value;
        _supply -= value;
        emit Transfer(from, address(0), value);
    }
}