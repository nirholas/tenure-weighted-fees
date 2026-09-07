// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/**
 * @title IHookMetadata
 * @notice On-chain self-description for Uniswap v4 hooks.
 * @dev Hook discovery today is off-chain: an indexer sees an unknown address in a `PoolKey` and has to guess what it
 * does from bytecode. This interface lets a hook answer that question itself, so aggregators, wallets, block explorers
 * and autonomous agents can classify a pool without a curated list. It is deliberately tiny: four view functions and an
 * ERC-165 id, all answerable from constants, so implementing it costs no storage and ~200 gas to query.
 *
 * `specURI` should resolve to a machine-readable document following the HookForge hook manifest schema
 * (https://hookforge.pages.dev/schema/hook-manifest.json), which carries the risk notes, parameters and audit status that do
 * not belong on-chain.
 */
interface IHookMetadata {
    /// @notice Human-readable name, e.g. "ArbTaxDecay".
    function hookName() external view returns (string memory);

    /// @notice Semantic version of the deployed implementation, e.g. "1.0.0".
    function hookVersion() external view returns (string memory);

    /// @notice URI of the machine-readable hook manifest describing parameters, risks and audits.
    function specURI() external view returns (string memory);

    /**
     * @notice Short classification tags, e.g. ["mev", "dynamic-fee", "lvr"].
     * @dev Tags are lowercase kebab-case and drawn from the HookForge taxonomy so that indexers can group hooks without
     * natural-language processing.
     */
    function hookTags() external view returns (string[] memory);
}
