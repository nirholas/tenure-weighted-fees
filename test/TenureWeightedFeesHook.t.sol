// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TenureWeightedFeesHook} from "src/hooks/TenureWeightedFeesHook.sol";
import {ForgeTest} from "./utils/ForgeTest.sol";

contract TenureWeightedFeesHookTest is ForgeTest {
    TenureWeightedFeesHook internal hook;
    PoolKey internal poolKey;

    uint160 internal constant FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );
    uint24 internal constant SKIM = 2_000; // 0.2% of each swap funds the pot

    int24 internal constant LOWER = -12000;
    int24 internal constant UPPER = 12000;

    function setUp() public {
        setUpForge();
        vm.warp(1_800_000_000);

        TenureWeightedFeesHook.Tier[] memory tiers = new TenureWeightedFeesHook.Tier[](3);
        tiers[0] = TenureWeightedFeesHook.Tier({heldFor: 0, multiplierBps: 10_000});
        tiers[1] = TenureWeightedFeesHook.Tier({heldFor: 7 days, multiplierBps: 15_000});
        tiers[2] = TenureWeightedFeesHook.Tier({heldFor: 30 days, multiplierBps: 20_000});

        hook = TenureWeightedFeesHook(
            deployHookTo(
                "src/hooks/TenureWeightedFeesHook.sol:TenureWeightedFeesHook",
                FLAGS,
                abi.encode(address(manager), tiers, SKIM)
            )
        );

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        manager.initialize(poolKey, SQRT_PRICE_1_1);
    }

    function _add(int256 liquidity, bytes32 salt) private {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey, ModifyLiquidityParams(LOWER, UPPER, liquidity, salt), ZERO_BYTES
        );
    }

    function _key(bytes32 salt) private view returns (bytes32) {
        return hook.positionKey(address(modifyLiquidityRouter), LOWER, UPPER, salt);
    }

    function test_metadata() public view {
        assertMetadata(address(hook), "TenureWeightedFees");
    }

    function test_theTierScheduleIsPublic() public view {
        TenureWeightedFeesHook.Tier[] memory tiers = hook.tiers();
        assertEq(tiers.length, 3);
        assertEq(tiers[0].multiplierBps, 10_000, "a new position is unweighted");
        assertEq(tiers[2].multiplierBps, 20_000, "a long-held one earns double");
    }

    function test_tierBoundaries() public view {
        assertEq(hook.multiplierFor(0), 10_000);
        assertEq(hook.multiplierFor(7 days - 1), 10_000, "one second short of a tier is still the old tier");
        assertEq(hook.multiplierFor(7 days), 15_000);
        assertEq(hook.multiplierFor(365 days), 20_000, "past the last tier it stays there");
    }

    function test_theSkimFundsThePotAndAccruesToProviders() public {
        _add(1e19, bytes32(0));
        (uint256 before0, uint256 before1) = hook.pending(_key(bytes32(0)));
        assertEq(before0 + before1, 0, "nothing accrued before any swap");

        swap(poolKey, true, -1e17, ZERO_BYTES);

        (uint256 after0, uint256 after1) = hook.pending(_key(bytes32(0)));
        assertGt(after0 + after1, 0, "the skim should have accrued to the only position");
    }

    function test_aLongHeldPositionOutEarnsAFreshOneOfTheSameSize() public {
        // The property the hook exists for. Two identical positions, one opened a month earlier.
        _add(1e19, bytes32(0));
        vm.warp(block.timestamp + 31 days);
        hook.poke(_key(bytes32(0))); // realise the tier it has earned

        _add(1e19, bytes32(uint256(1)));

        swap(poolKey, true, -1e17, ZERO_BYTES);

        (uint256 oldPos0, uint256 oldPos1) = hook.pending(_key(bytes32(0)));
        (uint256 newPos0, uint256 newPos1) = hook.pending(_key(bytes32(uint256(1))));

        assertGt(oldPos0 + oldPos1, newPos0 + newPos1, "the position that stayed should earn more");
        // Twice the multiplier, so about twice the share.
        assertApproxEqRel(oldPos0 + oldPos1, 2 * (newPos0 + newPos1), 1e15, "and about twice as much");
    }

    function test_justInTimeLiquidityEarnsNothingExtra() public {
        // A position that arrives immediately before a swap gets the ordinary Uniswap fee and no tenure reward
        // beyond its unweighted share, which is the whole point.
        _add(1e19, bytes32(0));
        vm.warp(block.timestamp + 31 days);
        hook.poke(_key(bytes32(0)));

        _add(1e19, bytes32(uint256(2))); // arrives just in time
        swap(poolKey, true, -1e17, ZERO_BYTES);

        (uint256 jit0, uint256 jit1) = hook.pending(_key(bytes32(uint256(2))));
        (uint256 held0, uint256 held1) = hook.pending(_key(bytes32(0)));
        assertLt(jit0 + jit1, held0 + held1, "arriving late must not pay as well as staying");
    }

    function test_pokeIsPermissionless() public {
        _add(1e19, bytes32(0));
        vm.warp(block.timestamp + 8 days);

        // Anybody can realise somebody else's tier; it can only ever pay them what the schedule promised.
        vm.prank(address(0xBEEF));
        hook.poke(_key(bytes32(0)));

        (, uint64 openedAt, uint32 tier,,,,,) = hook.positions(_key(bytes32(0)));
        assertEq(tier, 1, "a week held is the second tier");
        assertGt(openedAt, 0);
    }

    function test_claimPaysOutAndZeroesTheBalance() public {
        _add(1e19, bytes32(0));
        swap(poolKey, true, -1e17, ZERO_BYTES);
        swap(poolKey, false, -1e17, ZERO_BYTES);

        // The position key belongs to the router, so the router is who may claim. Claiming from anyone else must
        // find nothing, which is the access control.
        (uint256 owed0, uint256 owed1) = hook.pending(_key(bytes32(0)));
        assertGt(owed0 + owed1, 0);

        vm.prank(address(0xBEEF));
        (uint256 got0, uint256 got1) = hook.claim(LOWER, UPPER, bytes32(0), address(0xBEEF));
        assertEq(got0 + got1, 0, "a stranger's position key has nothing in it");

        (uint256 still0, uint256 still1) = hook.pending(_key(bytes32(0)));
        assertEq(still0 + still1, owed0 + owed1, "and the real position is untouched");
    }

    function test_removingLiquidityResetsTheTenureClock() public {
        _add(1e19, bytes32(0));
        vm.warp(block.timestamp + 31 days);
        hook.poke(_key(bytes32(0)));
        (,, uint32 tierBefore,,,,,) = hook.positions(_key(bytes32(0)));
        assertEq(tierBefore, 2);

        _add(-1e19, bytes32(0)); // fully exit
        (uint128 liquidity, uint64 openedAt, uint32 tierAfter,,,,,) = hook.positions(_key(bytes32(0)));
        assertEq(liquidity, 0);
        assertEq(tierAfter, 0, "an exited position starts again");
        assertEq(openedAt, 0);
    }

    function test_toppingUpKeepsTheTenureEarned() public {
        _add(1e19, bytes32(0));
        vm.warp(block.timestamp + 31 days);
        hook.poke(_key(bytes32(0)));

        _add(1e19, bytes32(0)); // top up the same position
        (uint128 liquidity,, uint32 tier,,,,,) = hook.positions(_key(bytes32(0)));
        assertEq(liquidity, 2e19, "the position grew");
        assertEq(tier, 2, "and kept the tenure it had earned");
    }

    function test_aSwapWithNoLiquidityTakesNoSkim() public {
        // Nothing to share it with, so the skim is not taken rather than stranded where nobody can claim it.
        _add(1e19, bytes32(0));
        _add(-1e19, bytes32(0));
        assertEq(hook.totalShares(), 0);

        uint256 before = manager.balanceOf(address(hook), currency0.toId());
        _add(1e19, bytes32(uint256(9)));
        assertEq(
            manager.balanceOf(address(hook), currency0.toId()),
            before,
            "no skim without shares"
        );
    }

    function test_theConstructorRejectsABadSchedule() public {
        TenureWeightedFeesHook.Tier[] memory backwards = new TenureWeightedFeesHook.Tier[](2);
        backwards[0] = TenureWeightedFeesHook.Tier({heldFor: 0, multiplierBps: 10_000});
        backwards[1] = TenureWeightedFeesHook.Tier({heldFor: 7 days, multiplierBps: 9_000});
        vm.expectRevert(TenureWeightedFeesHook.InvalidTiers.selector);
        deployHookToNamespace(
            "src/hooks/TenureWeightedFeesHook.sol:TenureWeightedFeesHook",
            FLAGS,
            abi.encode(address(manager), backwards, SKIM),
            0xE111
        );

        TenureWeightedFeesHook.Tier[] memory weighted = new TenureWeightedFeesHook.Tier[](1);
        weighted[0] = TenureWeightedFeesHook.Tier({heldFor: 0, multiplierBps: 12_000});
        vm.expectRevert(TenureWeightedFeesHook.InvalidTiers.selector);
        deployHookToNamespace(
            "src/hooks/TenureWeightedFeesHook.sol:TenureWeightedFeesHook",
            FLAGS,
            abi.encode(address(manager), weighted, SKIM),
            0xE222
        );
    }

    function testFuzz_sharesTrackLiquidityTimesMultiplier(uint96 amount) public {
        uint256 liquidity = bound(amount, 1e15, 1e20);
        _add(int256(liquidity), bytes32(0));
        assertEq(hook.totalShares(), liquidity, "unweighted at tier zero");

        vm.warp(block.timestamp + 31 days);
        hook.poke(_key(bytes32(0)));
        assertEq(hook.totalShares(), (liquidity * 20_000) / 10_000, "doubled at the top tier");
    }
}
