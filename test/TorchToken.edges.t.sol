// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {TorchToken} from "../src/TorchToken.sol";

/// @notice Edge cases the main suite leaves out: the full supply, one wei, the maximum uint256,
///         self-referential calls, zero-value calls without allowance, and event shape.
contract TorchTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    TorchToken internal token;
    address internal holder = makeAddr("holder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(holder);
        token = new TorchToken();
    }

    function test_transferWholeSupplyAndBack() public {
        vm.prank(holder);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        vm.prank(alice);
        token.transfer(holder, SUPPLY);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferOneWei() public {
        vm.prank(holder);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_transferOneWeiAboveSupplyReverts() public {
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_selfTransferAboveBalanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(alice, 1);
    }

    function test_zeroTransferToZeroAddressReverts() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferToTokenContractIsAcceptedAndStuck() public {
        // No recovery path exists; tokens sent to the contract itself are just held there.
        vm.prank(holder);
        token.transfer(address(token), 5);
        assertEq(token.balanceOf(address(token)), 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroValueWithoutAllowanceSucceeds() public {
        vm.prank(bob);
        assertTrue(token.transferFrom(holder, alice, 0));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, bob), 0);
    }

    function test_ownerNeedsOwnAllowanceForTransferFrom() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, holder, 0, 1));
        token.transferFrom(holder, alice, 1);

        vm.startPrank(holder);
        token.approve(holder, 3);
        assertTrue(token.transferFrom(holder, alice, 3));
        vm.stopPrank();
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(alice), 3);
    }

    function test_transferFromToSameAccountSpendsAllowanceKeepsBalance() public {
        vm.prank(holder);
        token.approve(bob, 10);
        vm.prank(bob);
        token.transferFrom(holder, holder, 10);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, bob), 0);
    }

    function test_allowanceOneBelowMaxIsDecremented() public {
        uint256 almost = type(uint256).max - 1;
        vm.prank(holder);
        token.approve(bob, almost);
        vm.prank(bob);
        token.transferFrom(holder, alice, 1);
        assertEq(token.allowance(holder, bob), almost - 1);
    }

    function test_unlimitedAllowanceStillBoundByBalance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, bob, 1);
    }

    function test_unlimitedAllowanceCanDrainWholeSupply() public {
        vm.prank(holder);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(holder, alice, SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(holder, bob), type(uint256).max);
    }

    function test_transferFromEmitsOnlyTransfer() public {
        vm.prank(holder);
        token.approve(bob, 10);
        vm.recordLogs();
        vm.prank(bob);
        token.transferFrom(holder, alice, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(holder))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), 4);
    }

    function test_revertedTransferFromLeavesNoLogsAndNoState() public {
        vm.prank(holder);
        token.approve(bob, 10);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(holder, address(0), 4);
        assertEq(token.allowance(holder, bob), 10);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_approveMaxEmitsMax() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(holder, bob, type(uint256).max);
        vm.prank(holder);
        token.approve(bob, type(uint256).max);
    }

    function test_approveZeroSpenderRevertsEvenForZeroValue() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_transferFromZeroOwnerNeedsAllowance() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(0), alice, 1);
    }

    function test_rejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_selfTransferIsNoOp(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(holder);
        token.transfer(holder, amount);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferRoundTrip(address to, uint256 amount) public {
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(holder);
        token.transfer(to, amount);
        vm.prank(to);
        token.transfer(holder, amount);
        assertEq(token.balanceOf(holder), SUPPLY);
        if (to != holder) assertEq(token.balanceOf(to), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_allowanceSpendsAddUp(uint256 allowed, uint256 first, uint256 second) public {
        allowed = bound(allowed, 0, SUPPLY);
        first = bound(first, 0, allowed);
        second = bound(second, 0, allowed - first);
        vm.prank(holder);
        token.approve(bob, allowed);
        vm.startPrank(bob);
        token.transferFrom(holder, alice, first);
        token.transferFrom(holder, alice, second);
        vm.stopPrank();
        assertEq(token.allowance(holder, bob), allowed - first - second);
        assertEq(token.balanceOf(alice), first + second);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_thirdPartyCannotMoveFunds(address stranger, uint256 amount) public {
        vm.assume(stranger != holder);
        amount = bound(amount, 1, SUPPLY);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(holder, stranger == address(0) ? alice : stranger, amount);
        assertEq(token.balanceOf(holder), SUPPLY);
    }
}
