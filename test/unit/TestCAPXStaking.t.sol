// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {CAPXStaking} from "../../src/CAPXStaking.sol";
import {CAPX} from "../../test/mocks/CAPX.sol";

contract TestCAPXStaking is Test {
    // ==================== State ====================

    CAPXStaking public staking;
    CAPX public capx;

    address public admin;
    address public treasury;
    address public dao;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant INITIAL_CAPX_BALANCE = 1_000_000 * 10 ** 18; // 1M CAPX
    uint256 public constant MIN_STAKE = 1000 * 10 ** 18; // 1000 CAPX

    // ==================== Setup ====================

    function setUp() public {
        // Create test addresses
        admin = _deployMockMultisig();
        treasury = makeAddr("treasury");
        dao = makeAddr("dao");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy CAPX token (admin is a contract for multisig requirement)
        vm.startPrank(admin);
        capx = new CAPX(admin, treasury, dao);

        // Deploy CAPXStaking contract
        staking = new CAPXStaking(admin, address(capx));
        vm.stopPrank();

        // Mint CAPX to users
        vm.startPrank(admin);
        capx.teamMint(user1, INITIAL_CAPX_BALANCE);
        capx.teamMint(user2, INITIAL_CAPX_BALANCE);
        capx.teamMint(user3, INITIAL_CAPX_BALANCE);

        // Mint reward pool to staking contract
        capx.teamMint(address(staking), 100_000 * 10 ** 18); // 100k CAPX for rewards

        // Mint some CAPX to admin for testing depositRewards
        capx.teamMint(admin, 50_000 * 10 ** 18);
        vm.stopPrank();

        // Approve staking contract to spend user CAPX
        vm.prank(user1);
        capx.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        capx.approve(address(staking), type(uint256).max);

        vm.prank(user3);
        capx.approve(address(staking), type(uint256).max);
    }

    // ==================== Stake Tests ====================

    function test_stake_flex_success() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.FLEX);
        assertEq(pos.amount, MIN_STAKE);
        assertEq(pos.unlockTime, block.timestamp); // FLEX has no lock
        assertTrue(pos.active);
        assertEq(uint8(pos.lockOption), uint8(CAPXStaking.LockOption.FLEX));
    }

    function test_stake_30days_success() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_30);
        assertEq(pos.amount, MIN_STAKE);
        assertEq(pos.unlockTime, block.timestamp + 30 days);
        assertTrue(pos.active);
    }

    function test_stake_90days_success() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_90);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_90);
        assertEq(pos.amount, MIN_STAKE);
        assertEq(pos.unlockTime, block.timestamp + 90 days);
        assertTrue(pos.active);
    }

    function test_stake_180days_success() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_180);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_180);
        assertEq(pos.amount, MIN_STAKE);
        assertEq(pos.unlockTime, block.timestamp + 180 days);
        assertTrue(pos.active);
    }

    function test_stake_multiple_positions_different_lock_options() public {
        vm.startPrank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_90);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_180);
        vm.stopPrank();

        CAPXStaking.Position[4] memory positions = staking.getAllPositions(user1);

        assertTrue(positions[0].active);
        assertTrue(positions[1].active);
        assertTrue(positions[2].active);
        assertTrue(positions[3].active);

        assertEq(staking.totalStaked(), MIN_STAKE * 4);
    }

    function test_stake_insufficient_amount() public {
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.InvalidAmount.selector);
        staking.stake(MIN_STAKE - 1, CAPXStaking.LockOption.FLEX);
    }

    function test_stake_duplicate_position_same_lock_option() public {
        vm.startPrank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        vm.expectRevert(CAPXStaking.PositionExists.selector);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);
        vm.stopPrank();
    }

    function test_stake_updates_totalStaked() public {
        uint256 stakeAmount = 5000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        assertEq(staking.totalStaked(), stakeAmount);
    }

    // ==================== Claim Tests ====================

    function test_claim_zero_reward() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        // Claim immediately (no time elapsed)
        vm.prank(user1);
        staking.claim(CAPXStaking.LockOption.FLEX);

        // Should not revert, just return early with no reward
        assertEq(capx.balanceOf(user1), INITIAL_CAPX_BALANCE - MIN_STAKE);
    }

    function test_claim_with_elapsed_time() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 claimable = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        assertGt(claimable, 0);

        vm.prank(user1);
        staking.claim(CAPXStaking.LockOption.FLEX);

        // User should have received rewards
        assertGt(capx.balanceOf(user1), INITIAL_CAPX_BALANCE - stakeAmount);
    }

    function test_claim_before_unlock() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);

        // Claim before unlock (should still work)
        vm.warp(block.timestamp + 10 days);

        vm.prank(user1);
        staking.claim(CAPXStaking.LockOption.DAYS_30);

        // Should not revert
        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_30);
        assertTrue(pos.active);
    }

    function test_claim_no_active_position() public {
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.NoActivePosition.selector);
        staking.claim(CAPXStaking.LockOption.FLEX);
    }

    // ==================== Compound Tests ====================

    function test_compound_success() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time and compound
        vm.warp(block.timestamp + 365 days);

        uint256 claimableBefore = staking.claimable(user1, CAPXStaking.LockOption.FLEX);

        vm.prank(user1);
        staking.compound(CAPXStaking.LockOption.FLEX);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.FLEX);
        assertEq(pos.amount, stakeAmount + claimableBefore);
        assertEq(staking.totalStaked(), stakeAmount + claimableBefore);
    }

    function test_compound_zero_reward() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        // Compound immediately (no reward)
        vm.prank(user1);
        staking.compound(CAPXStaking.LockOption.FLEX);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.FLEX);
        assertEq(pos.amount, MIN_STAKE);
    }

    function test_compound_during_lock_period() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_180);

        // Advance time (but not to unlock)
        vm.warp(block.timestamp + 90 days);

        // Should still be able to compound
        vm.prank(user1);
        staking.compound(CAPXStaking.LockOption.DAYS_180);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_180);
        assertTrue(pos.active);
    }

    // ==================== Unstake Tests ====================

    function test_unstake_flex_anytime() public {
        uint256 stakeAmount = MIN_STAKE;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Unstake immediately
        vm.prank(user1);
        staking.unstake(CAPXStaking.LockOption.FLEX);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.FLEX);
        assertFalse(pos.active);
        assertEq(staking.totalStaked(), 0);
    }

    function test_unstake_locked_before_unlock_reverts() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);

        // Try to unstake before unlock
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.StillLocked.selector);
        staking.unstake(CAPXStaking.LockOption.DAYS_30);
    }

    function test_unstake_locked_after_unlock() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);

        // Advance past unlock
        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(user1);
        staking.unstake(CAPXStaking.LockOption.DAYS_30);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_30);
        assertFalse(pos.active);
    }

    function test_unstake_includes_rewards() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        uint256 balanceBefore = capx.balanceOf(user1);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        vm.prank(user1);
        staking.unstake(CAPXStaking.LockOption.FLEX);

        uint256 balanceAfter = capx.balanceOf(user1);
        assertGt(balanceAfter, balanceBefore); // Should have more than initial balance
    }

    function test_unstake_no_active_position() public {
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.NoActivePosition.selector);
        staking.unstake(CAPXStaking.LockOption.FLEX);
    }

    // ==================== Admin Tests ====================

    function test_setBaseAprBps() public {
        uint256 newAprBps = 2400; // 24%

        vm.prank(admin);
        staking.setBaseAprBps(newAprBps);

        assertEq(staking.baseAprBps(), newAprBps);
    }

    function test_setBaseAprBps_exceeds_max() public {
        uint256 invalidAprBps = 10001; // > 100%

        vm.prank(admin);
        vm.expectRevert(CAPXStaking.InvalidRate.selector);
        staking.setBaseAprBps(invalidAprBps);
    }

    function test_setLockMultiplierBps() public {
        uint256 newMultiplier = 25000; // 2.5x

        vm.prank(admin);
        staking.setLockMultiplierBps(CAPXStaking.LockOption.DAYS_180, newMultiplier);

        assertEq(staking.lockMultiplierBps(CAPXStaking.LockOption.DAYS_180), newMultiplier);
    }

    function test_setLockMultiplierBps_below_minimum() public {
        uint256 invalidMultiplier = 9999; // < 1.0x

        vm.prank(admin);
        vm.expectRevert(CAPXStaking.InvalidRate.selector);
        staking.setLockMultiplierBps(CAPXStaking.LockOption.FLEX, invalidMultiplier);
    }

    function test_setMinStakeAmount() public {
        uint256 newMin = 5000 * 10 ** 18;

        vm.prank(admin);
        staking.setMinStakeAmount(newMin);

        assertEq(staking.minStakeAmount(), newMin);
    }

    function test_pause_unpause() public {
        vm.prank(admin);
        staking.pause();

        // Should revert when paused
        vm.prank(user1);
        vm.expectRevert();
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        // Unpause
        vm.prank(admin);
        staking.unpause();

        // Should work after unpause
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);
    }

    function test_depositRewards() public {
        uint256 rewardAmount = 10000 * 10 ** 18;

        vm.startPrank(admin);
        capx.approve(address(staking), rewardAmount);
        staking.depositRewards(rewardAmount);
        vm.stopPrank();

        // Check reward pool increased
        uint256 availableRewards = staking.availableRewards();
        assertGt(availableRewards, 0);
    }

    // ==================== View Functions Tests ====================

    function test_claimable_calculation() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        vm.warp(block.timestamp + 365 days);

        uint256 claimable = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        uint256 baseApr = staking.baseAprBps(); // 1200 = 12%
        uint256 expectedReward = (stakeAmount * baseApr * 365 days) / (10000 * 365 days);

        assertApproxEqAbs(claimable, expectedReward, 1e18); // Allow small rounding error
    }

    function test_totalClaimable_multiple_positions() public {
        uint256 stakeAmount = 5000 * 10 ** 18;

        vm.startPrank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);
        staking.stake(stakeAmount, CAPXStaking.LockOption.DAYS_30);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        uint256 totalClaimable = staking.totalClaimable(user1);
        uint256 claimableFlex = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        uint256 claimable30d = staking.claimable(user1, CAPXStaking.LockOption.DAYS_30);

        assertEq(totalClaimable, claimableFlex + claimable30d);
    }

    function test_effectiveAprBps() public {
        uint256 baseApr = staking.baseAprBps();
        uint256 multiplier = staking.lockMultiplierBps(CAPXStaking.LockOption.DAYS_180);

        uint256 effective = staking.effectiveAprBps(CAPXStaking.LockOption.DAYS_180);

        assertEq(effective, (baseApr * multiplier) / 10000);
    }

    // ==================== Reward Pool Depletion Tests ====================

    function test_claim_insufficient_rewards_pool() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time to accumulate rewards
        vm.warp(block.timestamp + 365 days);

        // Drain the reward pool completely by directly removing all CAPX
        uint256 contractBalance = capx.balanceOf(address(staking));
        vm.prank(address(staking));
        capx.transfer(admin, contractBalance - stakeAmount); // Leave exactly stakeAmount

        // Now try to claim - should fail with InsufficientRewards
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.InsufficientRewards.selector);
        staking.claim(CAPXStaking.LockOption.FLEX);
    }

    function test_unstake_insufficient_rewards_pool() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time and drain pool
        vm.warp(block.timestamp + 365 days);
        uint256 contractBalance = capx.balanceOf(address(staking));
        vm.prank(address(staking));
        capx.transfer(admin, contractBalance - stakeAmount);

        // Try to unstake - should fail with InsufficientRewards
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.InsufficientRewards.selector);
        staking.unstake(CAPXStaking.LockOption.FLEX);
    }

    function test_compound_insufficient_rewards_pool() public {
        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time and drain pool
        vm.warp(block.timestamp + 365 days);
        uint256 contractBalance = capx.balanceOf(address(staking));
        vm.prank(address(staking));
        capx.transfer(admin, contractBalance - stakeAmount);

        // Try to compound - should fail with InsufficientRewards
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.InsufficientRewards.selector);
        staking.compound(CAPXStaking.LockOption.FLEX);
    }

    // ==================== RecoverToken Tests ====================

    function test_recoverToken_cannot_recover_capx() public {
        uint256 amount = 1000 * 10 ** 18;
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        vm.expectRevert(CAPXStaking.CannotRecoverCAPX.selector);
        staking.recoverToken(address(capx), recipient, amount);
    }

    function test_recoverToken_zero_address_token() public {
        uint256 amount = 1000 * 10 ** 18;
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        vm.expectRevert(CAPXStaking.ZeroAddress.selector);
        staking.recoverToken(address(0), recipient, amount);
    }

    function test_recoverToken_zero_address_recipient() public {
        address someToken = makeAddr("token");
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(admin);
        vm.expectRevert(CAPXStaking.ZeroAddress.selector);
        staking.recoverToken(someToken, address(0), amount);
    }

    function test_recoverToken_zero_amount() public {
        address someToken = makeAddr("token");
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        vm.expectRevert(CAPXStaking.InvalidAmount.selector);
        staking.recoverToken(someToken, recipient, 0);
    }

    // ==================== Zero APR Tests ====================

    function test_setBaseAprBps_zero() public {
        vm.prank(admin);
        staking.setBaseAprBps(0);

        assertEq(staking.baseAprBps(), 0);
    }

    function test_zero_apr_no_rewards() public {
        vm.prank(admin);
        staking.setBaseAprBps(0);

        uint256 stakeAmount = 10000 * 10 ** 18;
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Claimable should be 0 with 0% APR
        uint256 claimable = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        assertEq(claimable, 0);
    }

    // ==================== Lock Duration Boundary Tests ====================

    function test_unstake_exactly_at_unlock_time() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_30);
        uint256 unlockTime = pos.unlockTime;

        // Warp to exactly unlock time
        vm.warp(unlockTime);

        // Should be able to unstake
        vm.prank(user1);
        staking.unstake(CAPXStaking.LockOption.DAYS_30);

        pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_30);
        assertFalse(pos.active);
    }

    function test_unstake_one_second_before_unlock() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.DAYS_30);

        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.DAYS_30);
        uint256 unlockTime = pos.unlockTime;

        // Warp to one second before unlock
        vm.warp(unlockTime - 1);

        // Should not be able to unstake
        vm.prank(user1);
        vm.expectRevert(CAPXStaking.StillLocked.selector);
        staking.unstake(CAPXStaking.LockOption.DAYS_30);
    }

    // ==================== Multiple Users / Competition Tests ====================

    function test_multiple_users_claim_same_pool() public {
        uint256 stakeAmount = 5000 * 10 ** 18;

        // Both users stake same amount
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        vm.prank(user2);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        uint256 user1Claimable = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        uint256 user2Claimable = staking.claimable(user2, CAPXStaking.LockOption.FLEX);

        // Both should have equal rewards (staked same amount at same time)
        assertEq(user1Claimable, user2Claimable);

        // User 1 claims
        vm.prank(user1);
        staking.claim(CAPXStaking.LockOption.FLEX);

        // User 2 should still be able to claim their rewards
        vm.prank(user2);
        staking.claim(CAPXStaking.LockOption.FLEX);

        // Both should have received rewards
        assertGt(capx.balanceOf(user1), INITIAL_CAPX_BALANCE - stakeAmount);
        assertGt(capx.balanceOf(user2), INITIAL_CAPX_BALANCE - stakeAmount);
    }

    function test_user_different_lock_options_compete_for_rewards() public {
        uint256 stakeAmount = 5000 * 10 ** 18;

        // User1 stakes FLEX, User2 stakes 180d
        vm.prank(user1);
        staking.stake(stakeAmount, CAPXStaking.LockOption.FLEX);

        vm.prank(user2);
        staking.stake(stakeAmount, CAPXStaking.LockOption.DAYS_180);

        vm.warp(block.timestamp + 365 days);

        // User2 should have higher rewards due to 2.0x multiplier
        uint256 user1Claimable = staking.claimable(user1, CAPXStaking.LockOption.FLEX);
        uint256 user2Claimable = staking.claimable(user2, CAPXStaking.LockOption.DAYS_180);

        // 180d has 2.0x multiplier vs FLEX 1.0x
        uint256 expectedRatio = 2; // user2 should have ~2x more
        assertGt(user2Claimable, user1Claimable);
        assertApproxEqAbs(user2Claimable, user1Claimable * expectedRatio, 1e17);
    }

    // ==================== Non-Reentrancy & Guard Tests ====================

    function test_pause_disables_stake_claim_compound() public {
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        vm.prank(admin);
        staking.pause();

        // Verify stake/claim/compound fail when paused
        vm.prank(user1);
        vm.expectRevert();
        staking.claim(CAPXStaking.LockOption.FLEX);

        vm.prank(user2);
        vm.expectRevert();
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        vm.prank(user1);
        vm.expectRevert();
        staking.compound(CAPXStaking.LockOption.FLEX);
    }

    function test_pause_allows_unstake_for_emergencies() public {
        // User1 stakes with FLEX lock
        vm.prank(user1);
        staking.stake(MIN_STAKE, CAPXStaking.LockOption.FLEX);

        // Admin pauses the contract
        vm.prank(admin);
        staking.pause();

        // Verify unstake still works when paused (for emergency withdrawals)
        vm.prank(user1);
        staking.unstake(CAPXStaking.LockOption.FLEX);

        // Position should be gone
        CAPXStaking.Position memory pos = staking.getPosition(user1, CAPXStaking.LockOption.FLEX);
        assertFalse(pos.active);
    }

    function test_non_owner_cannot_call_admin_functions() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.setBaseAprBps(1500);

        vm.prank(user1);
        vm.expectRevert();
        staking.setMinStakeAmount(2000 * 10 ** 18);

        vm.prank(user1);
        vm.expectRevert();
        staking.pause();
    }

    // ==================== Internal Helpers ====================

    function _deployMockMultisig() internal returns (address) {
        // Deploy a simple contract to act as multisig
        // This satisfies the AdminMustBeContract requirement
        return address(new MockMultisig());
    }

    function _stake(address user, uint256 amount, CAPXStaking.LockOption lockOption) internal {
        vm.prank(user);
        staking.stake(amount, lockOption);
    }

    function _claim(address user, CAPXStaking.LockOption lockOption) internal {
        vm.prank(user);
        staking.claim(lockOption);
    }

    function _compound(address user, CAPXStaking.LockOption lockOption) internal {
        vm.prank(user);
        staking.compound(lockOption);
    }

    function _unstake(address user, CAPXStaking.LockOption lockOption) internal {
        vm.prank(user);
        staking.unstake(lockOption);
    }
}

// Mock multisig contract
contract MockMultisig {
    fallback() external {}
}
