// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IHookMetadata} from "src/interfaces/IHookMetadata.sol";

/**
 * @title ForgeTest
 * @notice Shared harness for HookForge hook tests: a fresh `PoolManager`, two funded ERC-20s, routers, and helpers for
 * placing a hook at an address whose low bits encode its permission flags.
 */
abstract contract ForgeTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    function setUpForge() internal {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
    }

    /**
     * @notice Deploy `artifact` to the canonical address for `flags`, so `Hooks.validateHookPermissions` passes.
     * @param artifact Foundry artifact path, e.g. "src/hooks/ArbTaxDecayHook.sol:ArbTaxDecayHook".
     * @param flags Bitwise OR of the `Hooks.*_FLAG` constants the hook declares.
     * @param args ABI-encoded constructor arguments.
     */
    function deployHookTo(string memory artifact, uint160 flags, bytes memory args) internal returns (address hook) {
        return deployHookToNamespace(artifact, flags, args, 0x4444);
    }

    /**
     * @notice As {deployHookTo}, but with an explicit namespace, so one test can hold two hooks with identical flags.
     * @param namespace Any value; it only has to differ between hooks in the same test.
     */
    function deployHookToNamespace(string memory artifact, uint160 flags, bytes memory args, uint160 namespace)
        internal
        returns (address hook)
    {
        hook = address(flags | (namespace << 144));
        deployCodeTo(artifact, args, hook);
    }

    /// @notice The LP fee currently stored for `key`'s pool.
    function poolLpFee(PoolKey memory poolKey) internal view returns (uint24 lpFee) {
        (,,, lpFee) = manager.getSlot0(poolKey.toId());
    }

    /// @notice The pool's current sqrt price.
    function poolSqrtPrice(PoolKey memory poolKey) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,) = manager.getSlot0(poolKey.toId());
    }

    /// @notice Asserts the hook answers {IHookMetadata} with a non-empty name, version, spec URI and tag list.
    function assertMetadata(address hook, string memory expectedName) internal view {
        IHookMetadata meta = IHookMetadata(hook);
        assertEq(meta.hookName(), expectedName, "hookName");
        assertGt(bytes(meta.hookVersion()).length, 0, "hookVersion empty");
        assertGt(bytes(meta.specURI()).length, 0, "specURI empty");
        assertGt(meta.hookTags().length, 0, "hookTags empty");
    }
}
