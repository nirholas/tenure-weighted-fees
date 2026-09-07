// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {BaseHookFee} from "uniswap-hooks/fee/BaseHookFee.sol";

import {ForgeMetadata} from "../base/ForgeMetadata.sol";
import {ForgePayout} from "../base/ForgePayout.sol";

/**
 * @title TenureWeightedFeesHook
 * @notice Pays liquidity that stays more than liquidity that visits, by skimming a slice of every swap into a pot and
 * sharing it out in proportion to how long each position has been in the pool.
 *
 * @dev A Uniswap pool pays for capital present at the moment of a swap and is indifferent to everything else. That is
 * a defensible rule and it has a consequence: the most profitable way to provide liquidity is to not provide it. Wait
 * until a large trade is visible, add liquidity in front of it, collect the fee, and remove. The position existed for
 * two transactions, earned the same rate as capital that had been quoting for a month, and took none of the risk that
 * month carried.
 *
 * Just-in-time provision is the sharpest version, and hooks exist that penalise it directly. But the penalty is
 * treating a symptom: the pool's fee schedule genuinely does not distinguish a month of quoting from a moment of it,
 * and every provider who does the useful thing is underpaid relative to one who does not.
 *
 * This hook adds a second, parallel payment that does distinguish. It skims `skimBps` of every swap into a pot, and
 * shares the pot by tenure-weighted stake: a position's share is its liquidity multiplied by a tenure multiplier that
 * steps up as it stays. The ordinary Uniswap fee is untouched and still goes to whoever is in range, so nobody is
 * taxed for arriving; the tenure pot is simply money a passer-through never accrues any claim on.
 *
 * The multiplier steps at configured thresholds rather than growing continuously, and that is deliberate. A share
 * that grows continuously cannot be tracked by a reward accumulator without either re-deriving every position on
 * every swap or accepting drift. Discrete tiers change a position's share at known instants, which an accumulator
 * handles exactly, so nobody is short-changed by an approximation. A position's tier is applied when it is next
 * touched, and {poke} lets anybody touch any position, so realising an upgrade never depends on the pool being busy.
 *
 * Rewards accrue in whichever currency each swap paid them in, so the pot holds both. Claims settle both sides.
 *
 * @custom:slug tenure-weighted-fees
 * @custom:family Liquidity provider economics
 * @custom:prior-art Liquidity-mining schemes weight by liquidity and time, off-pool and funded by an emissions budget. LiquidityPenalty and the JIT-defence hooks punish short-lived positions. Curve's vote-escrow weights governance by lock length. Paying tenure out of the pool's own trading flow, alongside an untouched Uniswap fee, so that staying is rewarded without arriving being taxed, is the contribution here.
 * @custom:limitation Tenure is measured per position key, so a provider who removes and re-adds starts again, and one who tops up an existing position keeps their tier on the larger amount. That is the intended behaviour but it means the tier is a property of the position rather than of the provider, and a provider holding several positions accrues several independent tenures. The pot is also funded by a skim, so it is not free: swappers pay it, and a pool that sets `skimBps` too high will simply be routed around.
 * @custom:chains base,arbitrum,unichain,robinhood,ethereum,optimism,polygon,bnb
 */
contract TenureWeightedFeesHook is BaseHookFee, ForgeMetadata, ForgePayout {
    /// @notice Basis-point denominator.
    uint256 internal constant BPS = 10_000;

    /// @notice Fixed-point scale for the reward accumulator.
    uint256 internal constant ACC_PRECISION = 1e27;

    /// @notice The most tenure tiers a pool may define.
    uint256 public constant MAX_TIERS = 6;

    /// @notice A tenure threshold and what it multiplies a position's stake by.
    struct Tier {
        /// @notice Seconds a position must have been held to reach this tier.
        uint64 heldFor;
        /// @notice Multiplier applied at this tier, in basis points. `10000` is unweighted.
        uint32 multiplierBps;
    }

    /// @notice What the pool knows about one position.
    struct Position {
        /// @notice Raw liquidity the position holds.
        uint128 liquidity;
        /// @notice When it was first opened, which is what tenure is measured from.
        uint64 openedAt;
        /// @notice The tier last applied to it.
        uint32 tier;
        /// @notice Its tenure-weighted stake, as counted in `totalShares`.
        uint256 shares;
        /// @notice Accumulator checkpoints, one per currency.
        uint256 debt0;
        uint256 debt1;
        /// @notice Rewards earned and not yet taken.
        uint256 owed0;
        uint256 owed1;
    }

    /// @notice The tier schedule, fixed at deployment and ascending in both fields.
    Tier[] private _tiers;

    /// @notice The slice of each swap that funds the pot, in hundredths of a bip.
    uint24 public immutable skimBps;

    /// @notice The pool this hook serves, bound at its first initialization.
    PoolId public boundPool;

    /// @notice Every position's state, keyed by the v4 position key.
    mapping(bytes32 => Position) public positions;

    /// @notice Total tenure-weighted stake across all positions.
    uint256 public totalShares;

    /// @notice Reward accumulated per share, scaled by `ACC_PRECISION`, per currency.
    uint256 public accPerShare0;
    uint256 public accPerShare1;

    /// @dev The tier schedule was empty, too long, out of order, or started above the unweighted multiplier.
    error InvalidTiers();

    /// @dev The skim must leave the swap worth doing.
    error SkimTooLarge();

    /// @dev This hook serves one pool, bound at its first initialization.
    error WrongPool();

    /// @notice Emitted when a position's tenure tier changes.
    event TierApplied(bytes32 indexed position, uint32 tier, uint256 shares);

    /// @notice Emitted when a position takes its accrued rewards.
    event Claimed(bytes32 indexed position, address indexed to, uint256 amount0, uint256 amount1);

    constructor(IPoolManager _poolManager, Tier[] memory tiers_, uint24 _skimBps) BaseHook(_poolManager) {
        if (tiers_.length == 0 || tiers_.length > MAX_TIERS) revert InvalidTiers();
        if (tiers_[0].heldFor != 0 || tiers_[0].multiplierBps != BPS) revert InvalidTiers();
        // A skim above 10% is not a fee schedule, it is a toll, and a pool wearing one will simply be routed around.
        if (_skimBps > 100_000) revert SkimTooLarge();

        for (uint256 i = 0; i < tiers_.length; i++) {
            if (i > 0) {
                if (tiers_[i].heldFor <= tiers_[i - 1].heldFor) revert InvalidTiers();
                if (tiers_[i].multiplierBps <= tiers_[i - 1].multiplierBps) revert InvalidTiers();
            }
            _tiers.push(tiers_[i]);
        }
        skimBps = _skimBps;
    }

    /// @notice The tier schedule, so a provider can see what staying is worth before they commit.
    function tiers() external view returns (Tier[] memory) {
        return _tiers;
    }

    /// @notice The v4 position key for a range owned by `owner` with `salt`.
    function positionKey(address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt));
    }

    /// @notice The tier index a position of the given age qualifies for.
    function tierFor(uint256 heldSeconds) public view returns (uint32 tier) {
        for (uint256 i = _tiers.length; i > 0; i--) {
            // Casting to 'uint32' is safe because the loop index is bounded by MAX_TIERS.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (heldSeconds >= _tiers[i - 1].heldFor) return uint32(i - 1);
        }
        return 0;
    }

    /// @notice The multiplier a position of the given age earns, in basis points.
    function multiplierFor(uint256 heldSeconds) public view returns (uint256) {
        return _tiers[tierFor(heldSeconds)].multiplierBps;
    }

    /// @notice What `position` could claim right now, in each currency.
    function pending(bytes32 position) public view returns (uint256 amount0, uint256 amount1) {
        Position memory state = positions[position];
        amount0 = state.owed0 + ((state.shares * accPerShare0) / ACC_PRECISION) - state.debt0;
        amount1 = state.owed1 + ((state.shares * accPerShare1) / ACC_PRECISION) - state.debt1;
    }

    /**
     * @notice Apply a position's current tenure tier, raising its share of the pot.
     * @dev Callable by anyone for any position, because upgrading somebody's tier can only ever pay them what the
     * schedule already promised. Leaving it to the position's owner would mean a provider who stops watching quietly
     * keeps earning at a stale rate, which is a trap rather than a mechanism.
     */
    function poke(bytes32 position) public {
        Position storage state = positions[position];
        if (state.liquidity == 0) return;

        _settle(state);
        // Tenure is measured in days; the seconds a proposer can shift cannot move a tier boundary meaningfully.
        // forge-lint: disable-next-line(block-timestamp)
        uint32 tier = tierFor(block.timestamp - state.openedAt);
        if (tier == state.tier) return;

        uint256 newShares = (uint256(state.liquidity) * _tiers[tier].multiplierBps) / BPS;
        totalShares = totalShares - state.shares + newShares;
        state.shares = newShares;
        state.tier = tier;
        _checkpoint(state);

        emit TierApplied(position, tier, newShares);
    }

    /// @notice Take everything `position` has accrued. Callable only by the address that owns the position key.
    function claim(int24 tickLower, int24 tickUpper, bytes32 salt, address to)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        bytes32 position = positionKey(msg.sender, tickLower, tickUpper, salt);
        Position storage state = positions[position];

        _settle(state);
        (amount0, amount1) = (state.owed0, state.owed1);
        state.owed0 = 0;
        state.owed1 = 0;

        PoolKey memory key = _boundKey;
        // Paid as real tokens, not as claims: a rebate the recipient has to know to redeem is not a rebate.
        _payout(key.currency0, key.currency1, to, amount0, amount1);

        emit Claimed(position, to, amount0, amount1);
    }

    /// @dev The pool key this hook was bound to, kept so claims know which currencies to pay in.
    PoolKey private _boundKey;

    /// @dev Moves a position's earned rewards into `owed` and re-checkpoints it against the accumulator.
    function _settle(Position storage state) private {
        if (state.shares > 0) {
            state.owed0 += ((state.shares * accPerShare0) / ACC_PRECISION) - state.debt0;
            state.owed1 += ((state.shares * accPerShare1) / ACC_PRECISION) - state.debt1;
        }
        _checkpoint(state);
    }

    function _checkpoint(Position storage state) private {
        state.debt0 = (state.shares * accPerShare0) / ACC_PRECISION;
        state.debt1 = (state.shares * accPerShare1) / ACC_PRECISION;
    }

    /// @dev Binds the hook to one pool and records its key.
    function _afterInitialize(address, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        if (PoolId.unwrap(boundPool) != bytes32(0)) revert WrongPool();
        boundPool = key.toId();
        _boundKey = key;
        return this.afterInitialize.selector;
    }

    /// @dev Opens or grows a position, settling what it has earned first so the change is not applied retroactively.
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (params.liquidityDelta > 0) {
            bytes32 position = positionKey(sender, params.tickLower, params.tickUpper, params.salt);
            Position storage state = positions[position];
            _settle(state);

            // A brand-new position starts its tenure now. Topping up an existing one keeps the tenure it has earned,
            // which is why the clock is only set when the position was empty.
            // forge-lint: disable-next-line(block-timestamp)
            if (state.liquidity == 0) state.openedAt = uint64(block.timestamp);

            state.liquidity += uint128(uint256(params.liquidityDelta));
            uint256 newShares = (uint256(state.liquidity) * _tiers[state.tier].multiplierBps) / BPS;
            totalShares = totalShares - state.shares + newShares;
            state.shares = newShares;
            _checkpoint(state);
        }
        return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    /// @dev Shrinks a position. Rewards already earned stay claimable; the tenure clock restarts if it empties.
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (params.liquidityDelta < 0) {
            bytes32 position = positionKey(sender, params.tickLower, params.tickUpper, params.salt);
            Position storage state = positions[position];
            _settle(state);

            uint128 removed = uint128(uint256(-params.liquidityDelta));
            state.liquidity = removed >= state.liquidity ? 0 : state.liquidity - removed;

            uint256 newShares = (uint256(state.liquidity) * _tiers[state.tier].multiplierBps) / BPS;
            totalShares = totalShares - state.shares + newShares;
            state.shares = newShares;
            if (state.liquidity == 0) {
                state.tier = 0;
                state.openedAt = 0;
            }
            _checkpoint(state);
        }
        return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    /// @dev The slice of each swap that funds the pot.
    function _getHookFee(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        view
        override
        returns (uint24)
    {
        return skimBps;
    }

    /**
     * @dev Skims into the pot and shares it across the tenure-weighted stake.
     *
     * With no positions there is nothing to share, so the skim is not taken at all rather than being stranded in a
     * contract nobody can claim from.
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (totalShares == 0) return (this.afterSwap.selector, 0);

        (uint256 before0, uint256 before1) = _held(key);
        (bytes4 selector, int128 hookDelta) = super._afterSwap(sender, key, params, delta, hookData);
        _distribute(key, before0, before1);

        return (selector, hookDelta);
    }

    /// @dev What the hook currently holds of each of the pool's currencies, as ERC-6909 claims.
    function _held(PoolKey calldata key) private view returns (uint256 held0, uint256 held1) {
        held0 = poolManager.balanceOf(address(this), key.currency0.toId());
        held1 = poolManager.balanceOf(address(this), key.currency1.toId());
    }

    /// @dev Folds whatever the skim just took into the per-share accumulator.
    function _distribute(PoolKey calldata key, uint256 before0, uint256 before1) private {
        (uint256 after0, uint256 after1) = _held(key);
        if (after0 > before0) accPerShare0 += ((after0 - before0) * ACC_PRECISION) / totalShares;
        if (after1 > before1) accPerShare1 += ((after1 - before1) * ACC_PRECISION) / totalShares;
    }

    /**
     * @dev The base contract's hook for doing something with accumulated fees. This pool does not need it.
     *
     * Fees here are never accumulated in the sense the base means: each swap's skim is folded into the per-share
     * accumulator the moment it lands, and providers withdraw their share through {claim}. There is no pile of
     * unattributed value to sweep, which is the point of the design, so this is a no-op rather than a route by which
     * somebody could move funds that already belong to someone.
     */
    function handleHookFees(Currency[] memory) public pure override {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @inheritdoc ForgePayout
    function _payoutManager() internal view override returns (IPoolManager) {
        return poolManager;
    }

    function hookName() external pure override returns (string memory) {
        return "TenureWeightedFees";
    }

    function specURI() external pure override returns (string memory) {
        return string.concat(SPEC_BASE, "tenure-weighted-fees.json");
    }

    function hookTags() external pure override returns (string[] memory tags) {
        tags = new string[](5);
        tags[0] = "lp-economics";
        tags[1] = "tenure";
        tags[2] = "jit-defence";
        tags[3] = "rewards";
        tags[4] = "no-admin";
    }
}
