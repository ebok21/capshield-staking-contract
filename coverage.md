```bash
Compiling 36 files with Solc 0.8.30
Solc 0.8.30 finished in 1.12s
Compiler run successful with warnings:
Warning (2018): Function state mutability can be restricted to view
   --> test/unit/TestCAPXStaking.t.sol:423:5:
    |
423 |     function test_effectiveAprBps() public {
    |     ^ (Relevant source part starts here and spans across multiple lines).

Analysing contracts...
Running tests...

Ran 45 tests for test/unit/TestCAPXStaking.t.sol:TestCAPXStaking
[PASS] test_claim_before_unlock() (gas: 183740)
[PASS] test_claim_insufficient_rewards_pool() (gas: 193745)
[PASS] test_claim_no_active_position() (gas: 21629)
[PASS] test_claim_with_elapsed_time() (gas: 188035)
[PASS] test_claim_zero_reward() (gas: 159039)
[PASS] test_claimable_calculation() (gas: 162895)
[PASS] test_compound_during_lock_period() (gas: 171679)
[PASS] test_compound_insufficient_rewards_pool() (gas: 193702)
[PASS] test_compound_success() (gas: 178563)
[PASS] test_compound_zero_reward() (gas: 160188)
[PASS] test_depositRewards() (gas: 89999)
[PASS] test_effectiveAprBps() (gas: 14505)
[PASS] test_multiple_users_claim_same_pool() (gas: 296198)
[PASS] test_non_owner_cannot_call_admin_functions() (gas: 23021)
[PASS] test_pause_disables_all_operations() (gas: 178193)
[PASS] test_pause_unpause() (gas: 167368)
[PASS] test_recoverToken_cannot_recover_capx() (gas: 24301)
[PASS] test_recoverToken_zero_address_recipient() (gas: 22045)
[PASS] test_recoverToken_zero_address_token() (gas: 22110)
[PASS] test_recoverToken_zero_amount() (gas: 24374)
[PASS] test_setBaseAprBps() (gas: 21130)
[PASS] test_setBaseAprBps_exceeds_max() (gas: 13884)
[PASS] test_setBaseAprBps_zero() (gas: 16443)
[PASS] test_setLockMultiplierBps() (gas: 22647)
[PASS] test_setLockMultiplierBps_below_minimum() (gas: 14162)
[PASS] test_setMinStakeAmount() (gas: 21125)
[PASS] test_stake_180days_success() (gas: 155958)
[PASS] test_stake_30days_success() (gas: 155807)
[PASS] test_stake_90days_success() (gas: 155926)
[PASS] test_stake_duplicate_position_same_lock_option() (gas: 156750)
[PASS] test_stake_flex_success() (gas: 155740)
[PASS] test_stake_insufficient_amount() (gas: 21756)
[PASS] test_stake_multiple_positions_different_lock_options() (gas: 366868)
[PASS] test_stake_updates_totalStaked() (gas: 151555)
[PASS] test_totalClaimable_multiple_positions() (gas: 257759)
[PASS] test_unstake_exactly_at_unlock_time() (gas: 154050)
[PASS] test_unstake_flex_anytime() (gas: 145918)
[PASS] test_unstake_includes_rewards() (gas: 150494)
[PASS] test_unstake_insufficient_rewards_pool() (gas: 193770)
[PASS] test_unstake_locked_after_unlock() (gas: 150243)
[PASS] test_unstake_locked_before_unlock_reverts() (gas: 156653)
[PASS] test_unstake_no_active_position() (gas: 19343)
[PASS] test_unstake_one_second_before_unlock() (gas: 162513)
[PASS] test_user_different_lock_options_compete_for_rewards() (gas: 246169)
[PASS] test_zero_apr_no_rewards() (gas: 164470)
Suite result: ok. 45 passed; 0 failed; 0 skipped; finished in 32.49ms (206.28ms CPU time)

Ran 1 test suite in 33.85ms (32.49ms CPU time): 45 tests passed, 0 failed, 0 skipped (45 total tests)

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