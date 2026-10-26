// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TorchToken} from "../src/TorchToken.sol";

/// @notice Deploys the token the way the launch factory does: a contract's constructor-time
///         `new`, so `msg.sender` inside the token constructor is this deployer, not the test.
contract Deployer {
    TorchToken public immutable token;

    constructor() {
        token = new TorchToken();
    }

    function send(address to, uint256 value) external returns (bool) {
        return token.transfer(to, value);
    }

    function approveSpender(address spender, uint256 value) external returns (bool) {
        return token.approve(spender, value);
    }
}

contract TorchTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Deployer internal deployer;
    TorchToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = new Deployer();
        token = deployer.token();
    }

    // ------------------------------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Torch");
        assertEq(token.symbol(), "TORCH");
        assertEq(token.decimals(), 18);
        assertEq(token.NAME(), "Torch");
        assertEq(token.SYMBOL(), "TORCH");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        // Deploy a second instance directly to observe the event from the constructor.
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(this), SUPPLY);
        TorchToken fresh = new TorchToken();
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
    }

    function test_hasNoMintBurnOrAdminEntryPoints() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "setFee(uint256)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], address(this), SUPPLY);
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
    }

    // ------------------------------------------------------------------------------------------
    // transfer
    // ------------------------------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(deployer), alice, 1_000e18);
        assertTrue(deployer.send(alice, 1_000e18));
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - 1_000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferBetweenOrdinaryHolders() public {
        deployer.send(alice, 500e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 200e18));
        assertEq(token.balanceOf(alice), 300e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    function test_transferWholeBalance() public {
        deployer.send(alice, 500e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 500e18));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 500e18);
    }

    function test_transferZeroSucceedsAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 100e18));
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, alice, 100e18, 100e18 + 1));
        token.transfer(bob, 100e18 + 1);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, bob, 0, 1));
        token.transfer(alice, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ------------------------------------------------------------------------------------------
    // approve / allowance
    // ------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 42e18);
        vm.prank(alice);
        assertTrue(token.approve(bob, 42e18));
        assertEq(token.allowance(alice, bob), 42e18);
        assertEq(token.allowance(bob, alice), 0);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 10e18);
        token.approve(bob, 3e18);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 3e18);
        vm.prank(alice);
        token.approve(bob, 0);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(bob, SUPPLY));
        assertEq(token.allowance(alice, bob), SUPPLY);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ------------------------------------------------------------------------------------------
    // transferFrom
    // ------------------------------------------------------------------------------------------

    function test_transferFromSpendsAllowance() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, 60e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, carol, 40e18);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 40e18));

        assertEq(token.balanceOf(alice), 60e18);
        assertEq(token.balanceOf(carol), 40e18);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, bob), 20e18);
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, 60e18);
        vm.prank(bob);
        token.transferFrom(alice, carol, 60e18);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_transferFromUnlimitedAllowanceIsNotDecremented() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, carol, 70e18);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 70e18);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        deployer.send(alice, 100e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(alice, carol, 1);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_transferFromRevertsAboveAllowance() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, 10e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, bob, 10e18, 10e18 + 1));
        token.transferFrom(alice, carol, 10e18 + 1);
        assertEq(token.allowance(alice, bob), 10e18);
    }

    function test_transferFromRevertsAboveBalanceEvenWithAllowance() public {
        deployer.send(alice, 5e18);
        vm.prank(alice);
        token.approve(bob, 10e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, alice, 5e18, 6e18));
        token.transferFrom(alice, carol, 6e18);
        // Allowance untouched because the whole call reverted.
        assertEq(token.allowance(alice, bob), 10e18);
    }

    function test_transferFromRevertsToZeroAddress() public {
        deployer.send(alice, 5e18);
        vm.prank(alice);
        token.approve(bob, 10e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 1);
    }

    /// @dev The deployer, the most plausibly trusted address, cannot pull from a holder without
    ///      that holder's allowance. Mirrors the launch floor's privileged-hand check.
    function test_deployerCannotPullFromHolderWithoutAllowance() public {
        deployer.send(alice, 100e18);
        vm.prank(address(deployer));
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, address(deployer), 0, 1));
        token.transferFrom(alice, address(deployer), 1);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_allowanceIsPerSpender() public {
        deployer.send(alice, 100e18);
        vm.prank(alice);
        token.approve(bob, 50e18);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, carol, 0, 1));
        token.transferFrom(alice, carol, 1);
    }

    // ------------------------------------------------------------------------------------------
    // Launch flow shape: factory -> distributor -> claimant, with nothing lost
    // ------------------------------------------------------------------------------------------

    function test_launchFlowsMoveExactAmounts() public {
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address remainder = makeAddr("remainder");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = (SUPPLY * 8_000) / 10_000;
        uint256 rest = SUPPLY - swarm - pool;

        assertTrue(deployer.send(distributor, swarm));
        assertTrue(deployer.send(alice, pool)); // stands in for the pool manager
        assertTrue(deployer.send(remainder, rest));
        assertEq(token.balanceOf(address(deployer)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(alice), pool);
        assertEq(token.balanceOf(remainder), rest);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ------------------------------------------------------------------------------------------
    // Fuzz
    // ------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(deployer.send(to, amount));
        if (to == address(deployer)) {
            assertEq(token.balanceOf(address(deployer)), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(address(deployer)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 funded, uint256 attempt) public {
        funded = bound(funded, 0, SUPPLY - 1);
        attempt = bound(attempt, funded + 1, SUPPLY);
        deployer.send(alice, funded);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, alice, funded, attempt));
        token.transfer(bob, attempt);
    }

    function testFuzz_approveThenTransferFrom(uint256 funded, uint256 allowed, uint256 spend) public {
        funded = bound(funded, 0, SUPPLY);
        allowed = bound(allowed, 0, type(uint256).max - 1); // keep the unlimited case to its own test
        spend = bound(spend, 0, SUPPLY);
        deployer.send(alice, funded);
        vm.prank(alice);
        token.approve(bob, allowed);

        vm.prank(bob);
        if (spend > allowed) {
            vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientAllowance.selector, bob, allowed, spend));
            token.transferFrom(alice, carol, spend);
        } else if (spend > funded) {
            vm.expectRevert(abi.encodeWithSelector(TorchToken.ERC20InsufficientBalance.selector, alice, funded, spend));
            token.transferFrom(alice, carol, spend);
        } else {
            assertTrue(token.transferFrom(alice, carol, spend));
            assertEq(token.balanceOf(carol), spend);
            assertEq(token.balanceOf(alice), funded - spend);
            assertEq(token.allowance(alice, bob), allowed - spend);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_unlimitedAllowanceStaysUnlimited(uint256 funded, uint256 spend) public {
        funded = bound(funded, 0, SUPPLY);
        spend = bound(spend, 0, funded);
        deployer.send(alice, funded);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, spend));
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function testFuzz_randomTransfersNeverChangeTotalSupply(uint8 steps, bytes32 seed) public {
        address[3] memory holders = [alice, bob, carol];
        deployer.send(alice, SUPPLY / 3);
        deployer.send(bob, SUPPLY / 3);
        deployer.send(carol, SUPPLY - 2 * (SUPPLY / 3));
        uint256 rolling = uint256(seed);
        for (uint256 i; i < steps; ++i) {
            rolling = uint256(keccak256(abi.encode(rolling, i)));
            address from = holders[rolling % 3];
            address to = holders[(rolling / 3) % 3];
            uint256 amount = rolling % (token.balanceOf(from) + 1);
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
        }
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
