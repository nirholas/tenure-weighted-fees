# Deploying TenureWeightedFees

## Why it is not an ordinary deploy

Uniswap v4 reads a hook's permissions from the low fourteen bits of its address, and the `PoolManager` rejects a pool whose hook address does not match the permissions the hook declares. You cannot deploy a hook to whatever address you happen to get: you mine a CREATE2 salt until the address has the right bits, then deploy with that salt through a deterministic factory.

This hook needs `0x1544` in those bits, from claiming:

- `afterInitialize`
- `afterAddLiquidity`
- `afterRemoveLiquidity`
- `afterSwap`
- `afterSwapReturnsDelta`

## Running it

```bash
export PRIVATE_KEY=0x...
export RPC_URL=https://mainnet.base.org

# Dry run. Mines the salt, prints the address, sends nothing.
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# For real.
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

Mining is a view loop that never reaches the chain, but it does consume script gas. On some chains it exhausts the default limit and fails with `EvmError: OutOfGas` inside the miner rather than anywhere informative. `--gas-limit 30000000000` fixes it and costs nothing.

## The address differs per chain, on purpose

The hook takes its `PoolManager` as a constructor argument, so the init code differs per chain and so does the CREATE2 result. What is guaranteed is that the address is a pure function of (source, compiler settings, chain), which is the property that matters: anyone can re-run this script and derive the same address without trusting a published one.

## After deploying

1. Verify the source on the chain's explorer. `--verify` above does it if `ETHERSCAN_API_KEY` is set.
2. Submit the hook to [Uniswap's hooklist](https://github.com/Uniswap/hooklist), which takes a chain and an address and derives the rest from verified source. Being listed is not an endorsement and does not make a hook allowlisted for routing; the registry says so itself.
3. Publish the manifest at whatever URL the contract returns from `specURI()`. That string is immutable, so it has to resolve.

## Supported chains

Every chain with a Uniswap v4 `PoolManager`. The address book in [`src/libraries/Chains.sol`](../src/libraries/Chains.sol) carries the deployments this repository was built against, including Base, Arbitrum One, Unichain and Robinhood Chain.
