// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TorchToken} from "../src/TorchToken.sol";

/// @notice Drives the token with random sequences of transfer, approve and transferFrom across a
///         fixed set of actors, including calls that must revert. It keeps its own model of every
///         balance and allowance (ghosts) and checks each call's effect against it, so the
///         invariants below compare the token to an independent bookkeeping, not to itself.
contract TorchHandler is Test {
    TorchToken public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostTransfers;
    uint256 public ghostTransferFroms;
    uint256 public ghostApprovals;
    uint256 public ghostReverts;
    /// @dev Set if any call that should have reverted succeeded, or one that should have
    ///      succeeded reverted. Checked by an invariant so the failing sequence is reported.
    bool public ghostUnexpected;

    constructor(TorchToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        amount = bound(amount, 0, bal);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        if (!ok) ghostUnexpected = true;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostTransfers++;
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        excess = bound(excess, 1, type(uint256).max - bal);

        vm.prank(from);
        try token.transfer(to, bal + excess) {
            ghostUnexpected = true;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, from, bal, bal + excess)
                    )
            ) ghostUnexpected = true;
            ghostReverts++;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            ghostUnexpected = true;
        } catch {
            ghostReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        else amount = bound(amount, 0, 2 * token.TOTAL_SUPPLY());

        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) ghostUnexpected = true;
        ghostAllowance[owner][spender] = amount;
        ghostApprovals++;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 bal = ghostBalance[from];
        uint256 cap = allowed < bal ? allowed : bal;
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        bool ok = token.transferFrom(from, to, amount);
        if (!ok) ghostUnexpected = true;
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostTransferFroms++;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        excess = bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        try token.transferFrom(from, to, allowed + excess) {
            ghostUnexpected = true;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(
                            TorchToken.ERC20InsufficientAllowance.selector, spender, allowed, allowed + excess
                        )
                    )
            ) ghostUnexpected = true;
            ghostReverts++;
        }
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 bal = ghostBalance[from];
        if (allowed <= bal) return; // nothing above the balance is within the allowance
        excess = bound(excess, 1, allowed - bal);

        vm.prank(spender);
        try token.transferFrom(from, to, bal + excess) {
            ghostUnexpected = true;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, from, bal, bal + excess)
                    )
            ) ghostUnexpected = true;
            ghostReverts++;
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            ghostUnexpected = true;
        } catch {
            ghostReverts++;
        }
    }
}

contract TorchTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    TorchToken internal token;
    TorchHandler internal handler;
    address[] internal actors;

    function setUp() public {
        actors.push(makeAddr("deployer"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        vm.prank(actors[0]);
        token = new TorchToken();
        // Spread part of the supply so random sequences start with several funded holders.
        vm.startPrank(actors[0]);
        token.transfer(actors[1], SUPPLY / 4);
        token.transfer(actors[2], SUPPLY / 10);
        token.transfer(actors[3], 1);
        vm.stopPrank();

        handler = new TorchHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "balances of every possible holder do not sum to the supply");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_nothingLeaksOutsideTheActors() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everyCallBehavedAsSpecified() public view {
        assertFalse(handler.ghostUnexpected(), "a call succeeded or reverted against the specification");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "Torch");
        assertEq(token.symbol(), "TORCH");
        assertEq(token.decimals(), 18);
    }
}
