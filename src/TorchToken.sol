// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Torch (TORCH)
/// @notice A fixed-supply ERC-20 token. The whole supply, 1,000,000,000 TORCH with 18 decimals, is
///         minted once to the deployer in the constructor. There is no owner, no minting after
///         deployment, no pause, no blocklist, no fee and no burn on transfer: every transfer moves
///         exactly the amount asked for.
/// @dev Self-contained implementation of EIP-20 with the common extensions of the OpenZeppelin
///      interface (custom errors, unlimited allowance on `type(uint256).max`). The contract holds
///      no admin role at all, so nothing can be reconfigured after launch.
contract TorchToken {
    // ---------------------------------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------------------------------

    /// @notice Token name returned by `name()`.
    string public constant NAME = "Torch";

    /// @notice Token symbol returned by `symbol()`.
    string public constant SYMBOL = "TORCH";

    /// @notice Number of decimals; the supply below is expressed in these minor units.
    uint8 public constant DECIMALS = 18;

    /// @notice Whole supply in minor units: 1,000,000,000 * 10**18. Minted once, never again.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    // ---------------------------------------------------------------------------------------------
    // Events (EIP-20)
    // ---------------------------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ---------------------------------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------------------------------

    /// @notice `sender` tried to move `needed` but only holds `balance`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @notice `spender` tried to move `needed` on behalf of a holder but is only allowed `allowance`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    /// @notice The zero address was given as the receiver of a transfer.
    error ERC20InvalidReceiver(address receiver);
    /// @notice The zero address was given as the spender of an approval.
    error ERC20InvalidSpender(address spender);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ---------------------------------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the whole supply to the deployer (`msg.sender`). The launch factory deploys
    ///         this contract, so it receives the supply and pays it out according to the manifest.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    /// @notice Returns the token name.
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @notice Returns the token symbol.
    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    /// @notice Returns the number of decimals.
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    // ---------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------

    /// @notice Total supply in minor units. Fixed: nothing mints or burns after the constructor.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice Balance of `account` in minor units.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Remaining amount `spender` may move out of `owner`'s balance through `transferFrom`.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------------------------------------------------------------------------------------
    // Mutations
    // ---------------------------------------------------------------------------------------------

    /// @notice Moves `value` from the caller to `to`.
    /// @dev Reverts with `ERC20InvalidReceiver` for the zero address and `ERC20InsufficientBalance`
    ///      when the caller holds less than `value`. A zero-value transfer succeeds and emits.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Sets the caller's allowance for `spender` to `value`.
    /// @dev Overwrites the previous allowance; callers who want to avoid the approve race should
    ///      set it to zero first or compare the current allowance off chain.
    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` from `from` to `to` using the caller's allowance from `from`.
    /// @dev Only the allowance granted to `msg.sender` is spent; no address can move another
    ///      holder's tokens without that holder's approval. An allowance of `type(uint256).max` is
    ///      treated as unlimited and is not decremented.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(msg.sender, current, value);
            unchecked {
                _allowances[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 value) private {
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // Cannot underflow: checked above. Cannot overflow: the sum of all balances is TOTAL_SUPPLY.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
