// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title ForgePayout
 * @notice Turns a hook's ERC-6909 claims back into real tokens and sends them to somebody.
 *
 * @dev A hook that skims part of a swap holds the proceeds as ERC-6909 claims on the `PoolManager`, because taking
 * them as claims inside the swap costs a fraction of what taking real tokens would. That is the right way to hold
 * them and the wrong way to pay them out: transferring a claim hands the recipient a balance on a contract they have
 * never heard of, which they then have to know to redeem. A rebate nobody can spend is not a rebate.
 *
 * Paying out properly means burning the claim and taking the token, and both of those have to happen inside an
 * `unlock`. A hook is not inside one when somebody calls `claim`, so it opens one. This is the small amount of
 * plumbing that requires, in one place, so that no hook in the catalogue has to get it right twice.
 */
abstract contract ForgePayout is IUnlockCallback {
    /// @dev Only the `PoolManager` may drive the callback. Named distinctly because `BaseHook` declares its own.
    error PayoutNotPoolManager();

    /// @notice The `PoolManager` this hook is bound to. Provided by the inheriting hook.
    function _payoutManager() internal view virtual returns (IPoolManager);

    /**
     * @dev Sends `amount0` of `currency0` and `amount1` of `currency1` to `to` as real tokens.
     *
     * Zero amounts are skipped rather than settled, so a payout in one currency does not touch the other.
     */
    function _payout(Currency currency0, Currency currency1, address to, uint256 amount0, uint256 amount1) internal {
        if (amount0 == 0 && amount1 == 0) return;
        _payoutManager().unlock(abi.encode(currency0, currency1, to, amount0, amount1));
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        IPoolManager manager = _payoutManager();
        if (msg.sender != address(manager)) revert PayoutNotPoolManager();

        (Currency currency0, Currency currency1, address to, uint256 amount0, uint256 amount1) =
            abi.decode(data, (Currency, Currency, address, uint256, uint256));

        if (amount0 > 0) {
            manager.burn(address(this), currency0.toId(), amount0);
            manager.take(currency0, to, amount0);
        }
        if (amount1 > 0) {
            manager.burn(address(this), currency1.toId(), amount1);
            manager.take(currency1, to, amount1);
        }
        return "";
    }
}
