// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/test/shared/HookMiner.sol";

import {Chains} from "src/libraries/Chains.sol";
import {IHookMetadata} from "src/interfaces/IHookMetadata.sol";
import {TenureWeightedFeesHook} from "src/hooks/TenureWeightedFeesHook.sol";

/**
 * @title DeployTenureWeightedFees
 * @notice Deploys TenureWeightedFees deterministically to any chain with a Uniswap v4 `PoolManager`.
 *
 * @dev A v4 hook only works at an address whose low fourteen bits spell out the callbacks it implements, so the
 * deployment starts by mining a CREATE2 salt. Mining against `Chains.CREATE2_DEPLOYER` makes the result
 * reproducible: anyone can re-run this script and derive the same address without trusting a published one.
 *
 * The address is not the same on every chain, because the hook takes its `PoolManager` as a constructor argument
 * and that changes the init code. What is guaranteed is that the address is a pure function of (source, compiler
 * settings, chain).
 *
 * Usage:
 *
 *   forge script script/Deploy.s.sol --rpc-url $RPC_URL                       # dry run, sends nothing
 *   forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify  # for real
 *
 * Salt mining is a view loop that never reaches the chain, but it does consume script gas; some chains need
 * `--gas-limit 30000000000` or it fails with `EvmError: OutOfGas` inside the miner.
 *
 * Requires `PRIVATE_KEY` in the environment (or `--account` / `--ledger`). Re-running is safe: a hook already
 * deployed at its mined address is reported and skipped rather than redeployed.
 */
contract DeployTenureWeightedFees is Script {
    uint160 internal constant FLAGS = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);

    /// @notice Set before deploying: this is part of what the pool is, and it cannot change afterwards.
    tuple[] public tiers_;

    /// @notice Set before deploying: this is part of what the pool is, and it cannot change afterwards.
    uint24 public _skimBps;


    function run() external {
        IPoolManager manager = Chains.poolManager(block.chainid);
        require(address(manager) != address(0), "no Uniswap v4 PoolManager known for this chain");

        bytes memory creationCode = type(TenureWeightedFeesHook).creationCode;
        bytes memory constructorArgs = abi.encode(manager, tiers_, _skimBps);

        (address predicted, bytes32 salt) =
            HookMiner.find(Chains.CREATE2_DEPLOYER, FLAGS, creationCode, constructorArgs);

        console2.log("chain          ", block.chainid);
        console2.log("PoolManager    ", address(manager));
        console2.log("TenureWeightedFees ", predicted);

        if (predicted.code.length > 0) {
            console2.log("already deployed; nothing to do");
            return;
        }

        vm.startBroadcast();
        TenureWeightedFeesHook hook = new TenureWeightedFeesHook{salt: salt}(manager, tiers_, _skimBps);
        vm.stopBroadcast();

        require(address(hook) == predicted, "mined address did not match the deployment");
        // A hook that cannot say what it is defeats the point of the catalogue, so prove it answers before finishing.
        require(
            keccak256(bytes(IHookMetadata(address(hook)).hookName())) == keccak256(bytes("TenureWeightedFees")),
            "deployed hook does not identify itself"
        );

        console2.log("deployed and verified self-description");
    }
}
