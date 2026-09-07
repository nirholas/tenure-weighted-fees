# Integrating TenureWeightedFees

## From Solidity

```solidity
import {TenureWeightedFeesHook} from "tenure-weighted-fees/src/hooks/TenureWeightedFeesHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

PoolKey memory key = PoolKey({
    currency0: currencyA,          // must sort below currency1
    currency1: currencyB,
    fee: 3000,
    tickSpacing: 60,
    hooks: IHooks(address(hook))
});

poolManager.initialize(key, startingSqrtPriceX96);
```

## From TypeScript

```ts
import {getHook, hookAddress, poolKeyFor, poolId} from "@hookforge/sdk";

const hook = getHook("tenure-weighted-fees");
const address = hookAddress("tenure-weighted-fees", 8453);              // Base
const key = poolKeyFor({
  hook: address,
  currencyA: USDC,
  currencyB: WETH,
  tickSpacing: 60,
});
console.log(poolId(key));
```

## Identifying the hook from an address

Any caller holding only a hook address can find out what it is, without a registry:

```solidity
IHookMetadata(hookAddress).hookName();   // "TenureWeightedFees"
IHookMetadata(hookAddress).specURI();    // points at hook.json
```

The permission bits are in the address itself, so a caller can also decode what the hook participates in with no call at all:

```ts
import {permissionsOf} from "@hookforge/sdk";
permissionsOf(address);
```

## Things that will bite you

- **Deterministic addresses are not deployments.** An address published before a deploy is where the hook *will* be. There is no code at it until the deploy runs.

More at https://tenure-weighted-fees.pages.dev.
