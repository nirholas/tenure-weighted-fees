// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title Chains
 * @notice Canonical Uniswap v4 `PoolManager` addresses, keyed by chain id.
 * @dev Sourced from Uniswap's published deployment table. Keeping the address book in Solidity rather than in a
 * deployment script means a hook, a test and a script all resolve the same manager from `block.chainid` and cannot
 * drift apart. `CREATE2_DEPLOYER` is the deterministic deployment proxy Foundry broadcasts through, and is the
 * address hook salts must be mined against.
 */
library Chains {
    /// @dev No `PoolManager` is recorded for this chain id.
    error UnsupportedChain(uint256 chainId);

    /// @notice The deterministic CREATE2 proxy `forge script --broadcast` deploys through.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint256 internal constant ETHEREUM = 1;
    uint256 internal constant OPTIMISM = 10;
    uint256 internal constant BNB = 56;
    uint256 internal constant UNICHAIN = 130;
    uint256 internal constant POLYGON = 137;
    uint256 internal constant MONAD = 143;
    uint256 internal constant XLAYER = 196;
    uint256 internal constant WORLDCHAIN = 480;
    uint256 internal constant SONEIUM = 1868;
    uint256 internal constant TEMPO = 4217;
    uint256 internal constant MEGAETH = 4326;
    uint256 internal constant ROBINHOOD = 4663;
    uint256 internal constant BASE = 8453;
    uint256 internal constant ARBITRUM = 42161;
    uint256 internal constant AVALANCHE = 43114;
    uint256 internal constant CELO = 42220;
    uint256 internal constant INK = 57073;
    uint256 internal constant ZORA = 7777777;

    /// @notice The `PoolManager` for `chainId`, or revert if HookForge has no record of one.
    function poolManager(uint256 chainId) internal pure returns (IPoolManager) {
        if (chainId == ETHEREUM) return IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
        if (chainId == OPTIMISM) return IPoolManager(0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3);
        if (chainId == BNB) return IPoolManager(0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF);
        if (chainId == UNICHAIN) return IPoolManager(0x1F98400000000000000000000000000000000004);
        if (chainId == POLYGON) return IPoolManager(0x67366782805870060151383F4BbFF9daB53e5cD6);
        if (chainId == MONAD) return IPoolManager(0x188d586Ddcf52439676Ca21A244753fA19F9Ea8e);
        if (chainId == XLAYER) return IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        if (chainId == WORLDCHAIN) return IPoolManager(0xb1860D529182ac3BC1F51Fa2ABd56662b7D13f33);
        if (chainId == SONEIUM) return IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        if (chainId == TEMPO) return IPoolManager(0x33620f62C5b9B2086dD6b62F4A297A9f30347029);
        if (chainId == MEGAETH) return IPoolManager(0xaCB7e78fa05D562e0A5D3089ec896D57D057d38E);
        if (chainId == ROBINHOOD) return IPoolManager(0x8366a39CC670B4001A1121B8F6A443A643e40951);
        if (chainId == BASE) return IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);
        if (chainId == ARBITRUM) return IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        if (chainId == AVALANCHE) return IPoolManager(0x06380C0e0912312B5150364B9DC4542BA0DbBc85);
        if (chainId == CELO) return IPoolManager(0x288dc841A52FCA2707c6947B3A777c5E56cd87BC);
        if (chainId == INK) return IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        if (chainId == ZORA) return IPoolManager(0x0575338e4C17006aE181B47900A84404247CA30f);
        revert UnsupportedChain(chainId);
    }

    /// @notice The `PoolManager` for the chain this call is executing on.
    function poolManager() internal view returns (IPoolManager) {
        return poolManager(block.chainid);
    }

    /// @notice A short slug for `chainId`, matching the chain names Uniswap's hooklist registry uses.
    function slug(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM) return "ethereum";
        if (chainId == OPTIMISM) return "optimism";
        if (chainId == BNB) return "bnb";
        if (chainId == UNICHAIN) return "unichain";
        if (chainId == POLYGON) return "polygon";
        if (chainId == MONAD) return "monad";
        if (chainId == XLAYER) return "xlayer";
        if (chainId == WORLDCHAIN) return "worldchain";
        if (chainId == SONEIUM) return "soneium";
        if (chainId == TEMPO) return "tempo";
        if (chainId == MEGAETH) return "megaeth";
        if (chainId == ROBINHOOD) return "robinhood";
        if (chainId == BASE) return "base";
        if (chainId == ARBITRUM) return "arbitrum";
        if (chainId == AVALANCHE) return "avalanche";
        if (chainId == CELO) return "celo";
        if (chainId == INK) return "ink";
        if (chainId == ZORA) return "zora";
        revert UnsupportedChain(chainId);
    }
}
