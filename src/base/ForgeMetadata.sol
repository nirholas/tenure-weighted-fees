// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IHookMetadata} from "../interfaces/IHookMetadata.sol";

/**
 * @title ForgeMetadata
 * @notice On-chain self-description shared by every HookForge hook.
 * @dev Deliberately independent of `BaseHook` so that it can be mixed into any hook base (plain, fee-overriding,
 * custom-curve, async) without creating a diamond over `BaseHook`.
 */
abstract contract ForgeMetadata is IHookMetadata, IERC165 {
    /// @dev The HookForge contract release these hooks were published under.
    string internal constant FORGE_VERSION = "1.0.0";

    /// @dev Base URI for hook manifests: a hook's manifest lives at `SPEC_BASE + slug + ".json"`.
    string internal constant SPEC_BASE = "https://hookforge.pages.dev/schema/hooks/";

    /// @inheritdoc IHookMetadata
    function hookName() external view virtual returns (string memory);

    /// @inheritdoc IHookMetadata
    function hookVersion() external view virtual returns (string memory) {
        return FORGE_VERSION;
    }

    /// @inheritdoc IHookMetadata
    function specURI() external view virtual returns (string memory);

    /// @inheritdoc IHookMetadata
    function hookTags() external view virtual returns (string[] memory);

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IHookMetadata).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
