// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TorchToken} from "../src/TorchToken.sol";

/// @notice Structural checks the launch floor also applies: deployed through a stand-in factory
///         via CREATE2, the supply lands on the factory, the runtime fits EIP-170 and reachable
///         code carries no DELEGATECALL, CALLCODE or SELFDESTRUCT.
contract FactoryStandIn {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }
}

contract TorchTokenBytecodeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    FactoryStandIn internal factory;
    TorchToken internal token;

    function setUp() public {
        factory = new FactoryStandIn();
        token = TorchToken(factory.deploy(type(TorchToken).creationCode, bytes32(uint256(7))));
    }

    function test_create2DeploymentMintsToFactory() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
    }

    function test_create2AddressIsPredictable() public view {
        bytes32 codeHash = keccak256(type(TorchToken).creationCode);
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(uint256(7)), codeHash))))
        );
        assertEq(address(token), predicted);
    }

    function test_constructorTakesNoArguments() public {
        // Creation code with no appended arguments deploys; the launch manifest passes none.
        address again = factory.deploy(type(TorchToken).creationCode, bytes32(uint256(8)));
        assertEq(TorchToken(again).balanceOf(address(factory)), SUPPLY);
    }

    function test_runtimeFitsEip170() public view {
        uint256 size = address(token).code.length;
        assertGt(size, 0);
        assertLe(size, 24_576);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }
}
