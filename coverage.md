```bash
Compiling 37 files with Solc 0.8.30
Solc 0.8.30 finished in 1.44s
Compiler run successful with warnings:
Warning (2018): Function state mutability can be restricted to view
   --> test/unit/TestCAPXStaking.t.sol:423:5:
    |
423 |     function test_effectiveAprBps() public {
    |     ^ (Relevant source part starts here and spans across multiple lines).

Analysing contracts...
Running tests...

Ran 46 tests for test/unit/TestCAPXStaking.t.sol:TestCAPXStaking
[PASS] test_claim_before_unlock() (gas: 183740)
[PASS] test_claim_insufficient_rewards_pool() (gas: 193678)
[PASS] test_claim_no_active_position() (gas: 21651)
[PASS] test_claim_with_elapsed_time() (gas: 188057)
[PASS] test_claim_zero_reward() (gas: 159061)
[PASS] test_claimable_calculation() (gas: 162917)
[PASS] test_compound_during_lock_period() (gas: 171679)
[PASS] test_compound_insufficient_rewards_pool() (gas: 193724)
[PASS] test_compound_success() (gas: 178563)
[PASS] test_compound_zero_reward() (gas: 160210)
[PASS] test_depositRewards() (gas: 90021)
[PASS] test_effectiveAprBps() (gas: 14438)
[PASS] test_multiple_users_claim_same_pool() (gas: 296131)
[PASS] test_non_owner_cannot_call_admin_functions() (gas: 23021)
[PASS] test_pause_allows_unstake_for_emergencies() (gas: 151568)
[PASS] test_pause_disables_stake_claim_compound() (gas: 178129)
[PASS] test_pause_unpause() (gas: 167301)
[PASS] test_recoverToken_cannot_recover_capx() (gas: 24301)
[PASS] test_recoverToken_zero_address_recipient() (gas: 22067)
[PASS] test_recoverToken_zero_address_token() (gas: 22023)
[PASS] test_recoverToken_zero_amount() (gas: 24374)
[PASS] test_setBaseAprBps() (gas: 21152)
[PASS] test_setBaseAprBps_exceeds_max() (gas: 13906)
[PASS] test_setBaseAprBps_zero() (gas: 16465)
[PASS] test_setLockMultiplierBps() (gas: 22669)
[PASS] test_setLockMultiplierBps_below_minimum() (gas: 14184)
[PASS] test_setMinStakeAmount() (gas: 21147)
[PASS] test_stake_180days_success() (gas: 155980)
[PASS] test_stake_30days_success() (gas: 155829)
[PASS] test_stake_90days_success() (gas: 155970)
[PASS] test_stake_duplicate_position_same_lock_option() (gas: 156683)
[PASS] test_stake_flex_success() (gas: 155762)
[PASS] test_stake_insufficient_amount() (gas: 21778)
[PASS] test_stake_multiple_positions_different_lock_options() (gas: 366868)
[PASS] test_stake_updates_totalStaked() (gas: 151489)
[PASS] test_totalClaimable_multiple_positions() (gas: 257672)
[PASS] test_unstake_exactly_at_unlock_time() (gas: 154068)
[PASS] test_unstake_flex_anytime() (gas: 145936)
[PASS] test_unstake_includes_rewards() (gas: 150441)
[PASS] test_unstake_insufficient_rewards_pool() (gas: 193792)
[PASS] test_unstake_locked_after_unlock() (gas: 150260)
[PASS] test_unstake_locked_before_unlock_reverts() (gas: 156653)
[PASS] test_unstake_no_active_position() (gas: 19365)
[PASS] test_unstake_one_second_before_unlock() (gas: 162535)
[PASS] test_user_different_lock_options_compete_for_rewards() (gas: 246191)
[PASS] test_zero_apr_no_rewards() (gas: 164492)
Suite result: ok. 46 passed; 0 failed; 0 skipped; finished in 428.50ms (151.82ms CPU time)

Ran 18 tests for test/fuzz/FuzzCAPXStaking.t.sol:FuzzCAPXStaking
[PASS] testFuzz_claim_without_stake_reverts(uint8) (runs: 256, μ: 22920, ~: 23223)
[PASS] testFuzz_claimable_increases_with_time(uint256,uint256) (runs: 256, μ: 192655, ~: 192639)
[PASS] testFuzz_different_apr_values(uint256) (runs: 256, μ: 195504, ~: 196031)
[PASS] testFuzz_different_lock_multipliers(uint256) (runs: 256, μ: 28470, ~: 28760)
[PASS] testFuzz_rapid_stake_unstake_cycles(uint8) (runs: 256, μ: 614454, ~: 465133)
[PASS] testFuzz_reward_consistency_across_users(uint256,uint256) (runs: 256, μ: 290297, ~: 290400)
[PASS] testFuzz_stake_insufficient_amounts_reverts(uint256) (runs: 256, μ: 104494, ~: 103886)
[PASS] testFuzz_stake_valid_amounts(uint256,uint8) (runs: 256, μ: 184752, ~: 185097)
[PASS] testFuzz_very_large_stake_amounts(uint256) (runs: 256, μ: 183099, ~: 183170)
[PASS] testFuzz_zero_stake_amount_reverts() (gas: 22092)
[PASS] testInvariant_available_rewards_non_negative() (gas: 183312)
[PASS] testInvariant_claim_does_not_affect_principal() (gas: 234286)
[PASS] testInvariant_claim_resets_accumulation() (gas: 233723)
[PASS] testInvariant_compound_increases_principal() (gas: 202072)
[PASS] testInvariant_lock_period_enforced() (gas: 227769)
[PASS] testInvariant_one_position_per_lock_option() (gas: 525158)
[PASS] testInvariant_totalStaked_equals_sum_of_positions() (gas: 378746)
[PASS] testInvariant_unstake_removes_position() (gas: 217218)
Suite result: ok. 18 passed; 0 failed; 0 skipped; finished in 454.67ms (3.00s CPU time)

Ran 2 test suites in 456.50ms (883.17ms CPU time): 64 tests passed, 0 failed, 0 skipped (64 total tests)

╭---------------------+------------------+------------------+----------------+-----------------╮
| File                | % Lines          | % Statements     | % Branches     | % Funcs         |
+==============================================================================================+
| src/CAPXStaking.sol | 96.69% (117/121) | 93.88% (138/147) | 77.78% (21/27) | 100.00% (23/23) |
|---------------------+------------------+------------------+----------------+-----------------|
| test/mocks/CAPX.sol | 35.25% (49/139)  | 42.11% (48/114)  | 32.50% (13/40) | 18.18% (6/33)   |
|---------------------+------------------+------------------+----------------+-----------------|
| Total               | 63.85% (166/260) | 71.26% (186/261) | 50.75% (34/67) | 51.79% (29/56)  |
╰---------------------+------------------+------------------+----------------+-----------------╯
```