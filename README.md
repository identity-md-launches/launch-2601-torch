# Torch (TORCH)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Item | Value |
| --- | --- |
| Solidity contract | `TorchToken` (`src/TorchToken.sol`) |
| `name()` | `Torch` |
| `symbol()` | `TORCH` |
| `decimals()` | `18` |
| `totalSupply()` | `1000000000000000000000000000` (1,000,000,000 × 10^18) |
| Constructor arguments | none |
| Owner / admin | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"`, `cbor_metadata = false` |

## Behaviour

- The constructor mints the whole supply once to `msg.sender` and emits `Transfer(0x0, msg.sender, supply)`.
  At launch `msg.sender` is the ProjectFactory, which then pays the supply out (swarm share to the
  MerkleDistributor, pool share to the Uniswap v4 PoolManager, remainder to the requester).
- Standard EIP-20: `transfer`, `approve`, `transferFrom`, `allowance`, `balanceOf`, `totalSupply`,
  `name`, `symbol`, `decimals`, with the `Transfer` and `Approval` events.
- `transferFrom` spends only the allowance granted to `msg.sender`. An allowance of `type(uint256).max`
  is unlimited and is not decremented.
- Transfers to the zero address and approvals of the zero spender revert. Zero-value transfers succeed.
- There is no fee, tax, burn, reflection or exemption list. Every transfer moves exactly the amount
  asked for, so the launch flows (factory → distributor, distributor → claimant, factory → pool,
  pool ↔ trader) all arrive whole.
- There is no mint, burn, pause, blocklist, freeze, seize, upgrade or ownership function. The supply
  cannot grow or shrink after deployment and no address can move or lock another holder's balance.
- No `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`; no external calls of any kind; no libraries.

Custom errors follow the OpenZeppelin v5 naming (`ERC20InsufficientBalance`,
`ERC20InsufficientAllowance`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`) so standard tooling
decodes them.

## Deployment parameters

The contract is deployed by the launch factory from its creation code with **no constructor
arguments**. Nothing in the contract depends on the chain, the factory, the pool manager, the
launch number or the distributor; it needs no exemptions because it has no transfer rules.

Launch values decided by the launch itself (not open questions, listed for reference):

- Chain: Ethereum mainnet, chain id 1.
- Pair currency: IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals).
- Pool fee 12500 (1.25%), tick spacing 60.
- Economics: 80% of the supply seeds the pool, opening at a 2,500 IMD market cap for the whole supply;
  10% goes to the swarm's MerkleDistributor; the remaining 10% goes to
  `0x206f5dbf4f135c6183b5a5b99327fa0be34cb4d9`.

The manifest step writes `launch.json`; this repository does not contain one.

## After launch

Nothing to configure. The token has no owner and no settable storage.

## Assumptions

- The brief asks for a plain token: a name, a symbol and a supply minted to the deployer. No taxes,
  vesting, governance or burn mechanics were requested, so none are implemented.
- The factory is the deployer and therefore the initial holder of the entire supply. It is trusted
  to distribute the supply as the manifest says; the token cannot enforce or verify that.
- Holders are responsible for their own allowances. `approve` overwrites the previous allowance, so
  a spender that is being reduced should be set to zero first if the holder is worried about the
  classic approve race.
- The optimizer setting (200 runs) is a sensible default and is not a brief value; changing it changes
  the bytecode the launch hashes, so it should be left as is once the build is attested.

## Operational responsibilities

- **Requester / remainder wallet** (`0x206f…b4d9`): custody of the 10% remainder after launch.
- **IdentityMD deployer and factory**: deploying from the attested bytecode, forwarding the swarm share,
  seeding the pool and forwarding the remainder. This repository does not deploy, broadcast or hold keys.
- **Nobody** has an ongoing role in the contract: there is no owner to rotate, no parameter to tune and
  no pause to lift. Any future change requires a new token.

## Repository layout

```
foundry.toml          compiler pins and profile (solc 0.8.26, bytecode_hash none, no ffi, no fs access)
remappings.txt        forge-std/ -> lib/forge-std/src/
src/TorchToken.sol    the token
test/                 Foundry tests (unit, failure paths, fuzz, bytecode shape)
lib/forge-std/        vendored forge-std v1.11.0 (MIT / Apache-2.0), ordinary files, no submodule
```

## Building and testing

```
forge build
forge test
forge fmt --check
```

Fuzz tests are deterministic under any seed; the verifier's seed was used locally:

```
FOUNDRY_FUZZ_SEED=0xb0caabe2e06943a296bf61f7509b5eca128ce22cd906d216d9cbb21fe5a259fb forge test
```

Tests read no environment variables, do not use `ffi` or filesystem cheatcodes, and pass in any order
and in parallel.

### What the tests cover

- Metadata, supply and that the constructor mints everything to the deployer (through a contract
  that deploys the token, so `msg.sender` is a contract exactly as it is for the factory).
- CREATE2 deployment through a factory stand-in, address prediction, EIP-170 size, and a scan of the
  reachable runtime for `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT`.
- Success paths for `transfer`, `approve` and `transferFrom`, including zero-value, whole-balance,
  self-transfer and unlimited-allowance cases.
- Failure paths: insufficient balance, insufficient allowance, zero receiver, zero spender, a spender
  without an allowance, and the deployer trying to pull from a holder without approval.
- Absence of admin entry points: every common mint, burn, pause, blocklist, upgrade and ownership
  selector reverts when called from the deployer.
- Fuzz: supply conservation under arbitrary transfers, revert boundaries, allowance accounting.

## Security notes

Tests passing are not an audit. The contract follows the eth-security checklist items that apply to
a plain token: checked arithmetic (the only `unchecked` blocks are guarded by the preceding
comparison or bounded by the fixed supply), no external calls so no reentrancy surface, no
`selfdestruct`, no delegatecall or proxy, `transferFrom` moves tokens only through the caller's
allowance, and no `abi.encodePacked` of dynamic data. Slither and Mythril were not available on the
build machine and were not run; the verifier runs Slither. Independent adversarial review before
release is recommended as a matter of course, though this contract holds no funds and has no
privileged paths.
