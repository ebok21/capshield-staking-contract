// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {CAPXStaking} from "../../src/CAPXStaking.sol";
import {CAPX} from "../../test/mocks/CAPX.sol";

contract FuzzCAPXStaking is Test {
    // ==================== State ====================

    CAPXStaking public staking;
    CAPX public capx;

    address public admin;
    address public treasury;
    address public dao;

    uint256 public constant INITIAL_CAPX_BALANCE = 10_000_000 * 10 ** 18; // 10M CAPX per user
    uint256 public constant MIN_STAKE = 1000 * 10 ** 18; // 1000 CAPX
    uint256 public constant MAX_STAKE = 100_000 * 10 ** 18; // 100k CAPX (constrained for fuzz)

    // ==================== Setup ====================

    function setUp() public {
        // Create test addresses
        admin = address(new MockMultisig());
        treasury = makeAddr("treasury");
        dao = makeAddr("dao");

        // Deploy CAPX token
        vm.startPrank(admin);
        capx = new CAPX(admin, treasury, dao);

        // Deploy CAPXStaking contract
        staking = new CAPXStaking(admin, address(capx));
        vm.stopPrank();

        // Mint initial reward pool (smaller to avoid MAX_SUPPLY issues with fuzz)
        vm.startPrank(admin);
        capx.teamMint(address(staking), 50_000_000 * 10 ** 18); // 50M CAPX rewards
        vm.stopPrank();
    }

    // ==================== Fuzz Tests - Staking ====================

    function testFuzz_stake_valid_amounts(uint256 amount, uint8 lockOptionIdx) public {
        amount = bound(amount, MIN_STAKE, MAX_STAKE);
        lockOptionIdx = uint8(bound(lockOptionIdx, 0, 3));
        CAPXStaking.LockOption lockOption = CAPXStaking.LockOption(lockOptionIdx);

        address user = makeAddr("fuzz_user");
        vm.startPrank(admin);
        capx.teamMint(user, amount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), amount);
        staking.stake(amount, lockOption);
        vm.stopPrank();

        CAPXStaking.Position memory pos = staking.getPosition(user, lockOption);
        assertEq(pos.amount, amount);
        assertTrue(pos.active);
        assertEq(uint8(pos.lockOption), uint8(lockOption));
    }

    function testFuzz_stake_insufficient_amounts_reverts(uint256 amount) public {
        amount = bound(amount, 0, MIN_STAKE - 1);

        address user = makeAddr("fuzz_user");
        vm.startPrank(admin);
        capx.teamMint(user, MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), MIN_STAKE);
        vm.expectRevert(CAPXStaking.InvalidAmount.selector);
        staking.stake(amount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();
    }

    // ==================== Fuzz Tests - Rewards ====================

    function testFuzz_claimable_increases_with_time(uint256 stakeAmount, uint256 timeElapsed) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE, MAX_STAKE);
        timeElapsed = bound(timeElapsed, 0, 4 * 365 days);

        address user = makeAddr("fuzz_user");
        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        uint256 claimableBefore = staking.claimable(user, CAPXStaking.LockOption.FLEX);

        vm.warp(block.timestamp + timeElapsed);

        uint256 claimableAfter = staking.claimable(user, CAPXStaking.LockOption.FLEX);

        assertGe(claimableAfter, claimableBefore);
    }

    function testFuzz_different_apr_values(uint256 baseAprBps) public {
        baseAprBps = bound(baseAprBps, 0, 10000);

        vm.prank(admin);
        staking.setBaseAprBps(baseAprBps);

        assertEq(staking.baseAprBps(), baseAprBps);

        address user = makeAddr("fuzz_user");
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        uint256 claimable = staking.claimable(user, CAPXStaking.LockOption.FLEX);

        if (baseAprBps == 0) {
            assertEq(claimable, 0);
        } else {
            assertGt(claimable, 0);
        }
    }

    function testFuzz_different_lock_multipliers(uint256 multiplier) public {
        multiplier = bound(multiplier, 10000, 50000); // 1.0x to 5.0x

        vm.prank(admin);
        staking.setLockMultiplierBps(CAPXStaking.LockOption.DAYS_90, multiplier);

        uint256 baseApr = staking.baseAprBps();
        uint256 effective = staking.effectiveAprBps(CAPXStaking.LockOption.DAYS_90);

        assertEq(effective, (baseApr * multiplier) / 10000);
    }

    function testFuzz_reward_consistency_across_users(uint256 user1Amount, uint256 user2Amount) public {
        user1Amount = bound(user1Amount, MIN_STAKE, MAX_STAKE);
        user2Amount = bound(user2Amount, MIN_STAKE, MAX_STAKE);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.startPrank(admin);
        capx.teamMint(user1, user1Amount);
        capx.teamMint(user2, user2Amount);
        vm.stopPrank();

        vm.startPrank(user1);
        capx.approve(address(staking), user1Amount);
        staking.stake(user1Amount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.startPrank(user2);
        capx.approve(address(staking), user2Amount);
        staking.stake(user2Amount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        uint256 user1Claimable = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        uint256 user2Claimable = staking.claimable(user2, CAPXStaking.LockOption.FLEX);

        if (user1Amount > 0 && user1Claimable > 0) {
            uint256 expectedRatio = (user2Amount * 1e18) / user1Amount;
            uint256 actualRatio = (user2Claimable * 1e18) / user1Claimable;

            assertApproxEqRel(actualRatio, expectedRatio, 0.01e18);
        }
    }

    // ==================== Invariant Tests ====================

    function testInvariant_totalStaked_equals_sum_of_positions() public {
        address user1 = makeAddr("invariant_user1");
        address user2 = makeAddr("invariant_user2");
        address user3 = makeAddr("invariant_user3");

        uint256 stake1 = 5000 * 10 ** 18;
        uint256 stake2 = 7000 * 10 ** 18;
        uint256 stake3 = 3000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user1, stake1);
        capx.teamMint(user2, stake2);
        capx.teamMint(user3, stake3);
        vm.stopPrank();

        vm.startPrank(user1);
        capx.approve(address(staking), stake1);
        staking.stake(stake1, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.startPrank(user2);
        capx.approve(address(staking), stake2);
        staking.stake(stake2, CAPXStaking.LockOption.DAYS_30);
        vm.stopPrank();

        vm.startPrank(user3);
        capx.approve(address(staking), stake3);
        staking.stake(stake3, CAPXStaking.LockOption.DAYS_180);
        vm.stopPrank();

        uint256 expectedTotal = stake1 + stake2 + stake3;
        assertEq(staking.totalStaked(), expectedTotal);
    }

    function testInvariant_available_rewards_non_negative() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        uint256 availableRewards = staking.availableRewards();
        assertGe(availableRewards, 0);

        uint256 contractBalance = capx.balanceOf(address(staking));
        uint256 totalStaked = staking.totalStaked();

        if (contractBalance >= totalStaked) {
            assertEq(availableRewards, contractBalance - totalStaked);
        } else {
            assertEq(availableRewards, 0);
        }
    }

    function testInvariant_compound_increases_principal() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        CAPXStaking.Position memory posBefore = staking.getPosition(user, CAPXStaking.LockOption.FLEX);
        uint256 amountBefore = posBefore.amount;

        vm.prank(user);
        staking.compound(CAPXStaking.LockOption.FLEX);

        CAPXStaking.Position memory posAfter = staking.getPosition(user, CAPXStaking.LockOption.FLEX);
        uint256 amountAfter = posAfter.amount;

        assertGe(amountAfter, amountBefore);
    }

    function testInvariant_claim_does_not_affect_principal() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        CAPXStaking.Position memory posBefore = staking.getPosition(user, CAPXStaking.LockOption.FLEX);

        vm.prank(user);
        staking.claim(CAPXStaking.LockOption.FLEX);

        CAPXStaking.Position memory posAfter = staking.getPosition(user, CAPXStaking.LockOption.FLEX);

        assertEq(posAfter.amount, posBefore.amount);
        assertGt(posAfter.lastClaimTime, posBefore.lastClaimTime);
    }

    function testInvariant_unstake_removes_position() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        assertTrue(staking.getPosition(user, CAPXStaking.LockOption.FLEX).active);

        vm.prank(user);
        staking.unstake(CAPXStaking.LockOption.FLEX);

        assertFalse(staking.getPosition(user, CAPXStaking.LockOption.FLEX).active);
    }

    function testInvariant_one_position_per_lock_option() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 5000 * 10 ** 18;

        for (uint8 i = 0; i < 4; i++) {
            vm.startPrank(admin);
            capx.teamMint(user, stakeAmount);
            vm.stopPrank();

            vm.startPrank(user);
            capx.approve(address(staking), stakeAmount);
            staking.stake(stakeAmount, CAPXStaking.LockOption(i));
            vm.stopPrank();
        }

        CAPXStaking.Position[4] memory positions = staking.getAllPositions(user);
        for (uint8 i = 0; i < 4; i++) {
            assertTrue(positions[i].active);
        }

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();
        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        vm.expectRevert(CAPXStaking.PositionExists.selector);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();
    }

    function testInvariant_lock_period_enforced() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.DAYS_90);
        vm.stopPrank();

        CAPXStaking.Position memory pos = staking.getPosition(user, CAPXStaking.LockOption.DAYS_90);
        uint256 unlockTime = pos.unlockTime;

        vm.warp(unlockTime - 1);
        vm.prank(user);
        vm.expectRevert(CAPXStaking.StillLocked.selector);
        staking.unstake(CAPXStaking.LockOption.DAYS_90);

        vm.warp(unlockTime);
        vm.prank(user);
        staking.unstake(CAPXStaking.LockOption.DAYS_90);

        assertFalse(staking.getPosition(user, CAPXStaking.LockOption.DAYS_90).active);
    }

    function testInvariant_claim_resets_accumulation() public {
        address user = makeAddr("invariant_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.teamMint(user, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 100 days);

        vm.prank(user);
        staking.claim(CAPXStaking.LockOption.FLEX);

        uint256 claimableAfterClaim = staking.claimable(user, CAPXStaking.LockOption.FLEX);
        assertEq(claimableAfterClaim, 0);

        vm.warp(block.timestamp + 100 days);
        uint256 claimable2 = staking.claimable(user, CAPXStaking.LockOption.FLEX);
        assertGt(claimable2, 0);
    }

    // ==================== Edge Case Fuzz Tests ====================

    function testFuzz_zero_stake_amount_reverts() public {
        address user = makeAddr("fuzz_user");

        vm.startPrank(user);
        vm.expectRevert(CAPXStaking.InvalidAmount.selector);
        staking.stake(0, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();
    }

    function testFuzz_very_large_stake_amounts(uint256 amount) public {
        // Test large stake amounts that are still within uint128 and MAX_SUPPLY
        amount = bound(amount, MAX_STAKE, 10_000_000 * 10 ** 18);

        address user = makeAddr("fuzz_user");

        vm.startPrank(admin);
        capx.teamMint(user, amount);
        vm.stopPrank();

        vm.startPrank(user);
        capx.approve(address(staking), amount);
        staking.stake(amount, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();

        CAPXStaking.Position memory pos = staking.getPosition(user, CAPXStaking.LockOption.FLEX);
        assertEq(pos.amount, amount);
    }

    function testFuzz_rapid_stake_unstake_cycles(uint8 cycles) public {
        cycles = uint8(bound(cycles, 1, 10));
        address user = makeAddr("fuzz_user");
        uint256 stakeAmount = 10000 * 10 ** 18;

        for (uint8 i = 0; i < cycles; i++) {
            vm.startPrank(admin);
            capx.teamMint(user, stakeAmount);
            vm.stopPrank();

            vm.startPrank(user);
            capx.approve(address(staking), stakeAmount);
            staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
            vm.stopPrank();

            vm.warp(block.timestamp + 1 seconds);

            vm.prank(user);
            staking.unstake(CAPXStaking.LockOption.FLEX);

            assertFalse(staking.getPosition(user, CAPXStaking.LockOption.FLEX).active);
        }
    }

    function testFuzz_claim_without_stake_reverts(uint8 lockOptionIdx) public {
        lockOptionIdx = uint8(bound(lockOptionIdx, 0, 3));
        address user = makeAddr("fuzz_user");

        vm.prank(user);
        vm.expectRevert(CAPXStaking.NoActivePosition.selector);
        staking.claim(CAPXStaking.LockOption(lockOptionIdx));
    }
}

// Mock multisig contract
contract MockMultisig {
    fallback() external {}
}
