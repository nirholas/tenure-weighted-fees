# TenureWeightedFees

**Pays liquidity that stays more than liquidity that visits, by skimming a slice of every swap into a pot and sharing it out in proportion to how long each position has been in the pool.**

A production Uniswap v4 hook. It holds no funds and takes no fee for itself. No owner, no pause switch, no upgrade path.

- **Site:** https://tenure-weighted-fees.pages.dev
- **Catalogue:** https://hookforge.pages.dev
- **Contract:** [`src/hooks/TenureWeightedFeesHook.sol`](src/hooks/TenureWeightedFeesHook.sol)
- **Licence:** Apache-2.0

## How it works

A Uniswap pool pays for capital present at the moment of a swap and is indifferent to everything else. That is a defensible rule and it has a consequence: the most profitable way to provide liquidity is to not provide it. Wait until a large trade is visible, add liquidity in front of it, collect the fee, and remove.

The position existed for two transactions, earned the same rate as capital that had been quoting for a month, and took none of the risk that month carried. Just-in-time provision is the sharpest version, and hooks exist that penalise it directly. But the penalty is treating a symptom: the pool's fee schedule genuinely does not distinguish a month of quoting from a moment of it, and every provider who does the useful thing is underpaid relative to one who does not.

This hook adds a second, parallel payment that does distinguish. It skims `skimBps` of every swap into a pot, and shares the pot by tenure-weighted stake: a position's share is its liquidity multiplied by a tenure multiplier that steps up as it stays. The ordinary Uniswap fee is untouched and still goes to whoever is in range, so nobody is taxed for arriving; the tenure pot is simply money a passer-through never accrues any claim on.

The multiplier steps at configured thresholds rather than growing continuously, and that is deliberate. A share that grows continuously cannot be tracked by a reward accumulator without either re-deriving every position on every swap or accepting drift. Discrete tiers change a position's share at known instants, which an accumulator handles exactly, so nobody is short-changed by an approximation.

A position's tier is applied when it is next touched, and {poke} lets anybody touch any position, so realising an upgrade never depends on the pool being busy. Rewards accrue in whichever currency each swap paid them in, so the pot holds both. Claims settle both sides.

## Prior art

Liquidity-mining schemes weight by liquidity and time, off-pool and funded by an emissions budget. LiquidityPenalty and the JIT-defence hooks punish short-lived positions. Curve's vote-escrow weights governance by lock length. Paying tenure out of the pool's own trading flow, alongside an untouched Uniswap fee, so that staying is rewarded without arriving being taxed, is the contribution here.

## Where it does not help

Tenure is measured per position key, so a provider who removes and re-adds starts again, and one who tops up an existing position keeps their tier on the larger amount. That is the intended behaviour but it means the tier is a property of the position rather than of the provider, and a provider holding several positions accrues several independent tenures. The pot is also funded by a skim, so it is not free: swappers pay it, and a pool that sets `skimBps` too high will simply be routed around.

## Using it

Uniswap v4 removed `hookData` from `initialize`, so per-pool parameters arrive out of band. Fix them for a pool key whose pool does not exist yet, then initialize. Nobody can change them afterwards, including you.

```solidity
// This hook needs no configuration.

poolManager.initialize(key, startingSqrtPriceX96);
```


### Parameters

This hook takes no per-pool configuration.

## What it reverts with

| Error | Meaning |
| --- | --- |
| `HookFeeTooLarge()` | Fee is higher than the maximum allowed fee. |
| `InvalidTiers()` | The tier schedule was empty, too long, out of order, or started above the unweighted multiplier. |
| `PayoutNotPoolManager()` | Only the `PoolManager` may drive the callback. Named distinctly because `BaseHook` declares its own. |
| `SkimTooLarge()` | The skim must leave the swap worth doing. |
| `WrongPool()` | This hook serves one pool, bound at its first initialization. |

## The callbacks it claims

Uniswap v4 reads a hook's permissions from the low fourteen bits of its own address, which is why deploying one means mining a CREATE2 salt. This hook claims 5 of the fourteen:

- `afterInitialize`
- `afterAddLiquidity`
- `afterRemoveLiquidity`
- `afterSwap`
- `afterSwapReturnsDelta`

Mask: `0x1544`, so every deployment of this hook has an address ending in those bits.

## It says what it is, on-chain

Every hook in this family implements `IHookMetadata`: four view functions that let an indexer, a wallet, a router or an agent identify a hook from its address alone, with no registry in the loop.

```bash
cast call $HOOK "hookName()(string)"    # TenureWeightedFees
cast call $HOOK "hookVersion()(string)" # 1.0.0
cast call $HOOK "specURI()(string)"     # the machine-readable manifest
cast call $HOOK "hookTags()(string[])"  # lp-economics, tenure, jit-defence, rewards, no-admin
```

The manifest this repository ships as [`hook.json`](hook.json) is what `specURI()` points at.

## Build and test

```bash
git clone --recurse-submodules https://github.com/nirholas/tenure-weighted-fees
cd tenure-weighted-fees
forge build
forge test
```

Foundry 1.7 or newer, Solidity 0.8.26, EVM version `cancun` (Uniswap v4 requires transient storage).

## Deploy

```bash
# Dry run: mines the salt and prints the address without sending anything.
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# For real.
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

Needs `PRIVATE_KEY` in the environment and a funded deployer on the target chain. See [`docs/deploying.md`](docs/deploying.md).

## Status

**Unaudited.** Built to an audited shape, on OpenZeppelin's audited hook bases, and tested against a real `PoolManager`. No third party has reviewed it. Read "where it does not help" above before putting money behind it.

Not affiliated with Uniswap Labs.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=nirholas/tenure-weighted-fees&type=Date)](https://www.star-history.com/#nirholas/tenure-weighted-fees&Date)
