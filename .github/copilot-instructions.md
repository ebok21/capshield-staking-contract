# Copilot Instructions for CAPXStaking Contract

## Project Overview
**CAPXStaking** is a single-position ERC20 staking contract for CAPX tokens built with Foundry/Solidity 0.8.30.

### Key Architecture
- **One position per user**: Each address can hold only ONE active staking position at a time
- **Lock options**: FLEX (no lock), 30 days, 90 days, 180 days with multipliers (1.0x to 2.0x APR boost)
- **Reward system**: APR calculated in basis points, applied to principal amount, compounded by user action
- **Immutable CAPX token**: Stored as immutable state variable; cannot be recovered
- **Pauseable**: Owner can pause all operations (stake/claim/compound/unstake)
- **Multisig requirement**: Owner MUST be a contract (enforced in constructor)

## Core Mechanics & Rules
1. **Staking**: Users call `stake(amount, lockOption)` with minimum amount. Principal cannot be modified post-stake.
2. **Rewards**: Paid from `balanceOf(this) - totalStaked`. User must claim manually or compound.
3. **Unstaking**: Only allowed after lock period expires (FLEX has 0 duration). Auto-claims pending rewards.
4. **Compounding**: `compound()` adds rewards to principal without token transfer—increases earning basis.
5. **Lock multipliers**: Defined per-option; final APR = `baseAprBps * lockMultiplierBps[option] / 10_000`

## Critical Patterns & Conventions

### Reward Calculation
```solidity
// In _claimableRewardView(Position memory p)
uint256 aprBps = (baseAprBps * multiplier) / BPS_DENOMINATOR;
return (uint256(p.amount) * aprBps * elapsed) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
```
- Uses basis points (10,000 = 100%) to avoid decimals
- **SECONDS_PER_YEAR = 365 days** (immutable constant)
- Elapsed time from `lastClaimTime` to `block.timestamp`

### State Updates Pattern
When implementing state changes:
1. Fetch position from storage
2. Validate pre-conditions (active, not locked, etc.)
3. Update state variables atomically
4. Emit event with old/new values
5. Use `nonReentrant` + `whenNotPaused` guards

### Error Handling
Custom errors (not revert strings) for gas efficiency:
- `PositionExists()` – user already has active stake
- `NoActivePosition()` – user has no stake
- `StillLocked()` – principal unlock time not reached
- `InsufficientRewards()` – reward pool exhausted (can happen if interest accrues beyond available balance)

## Workflow & Commands

### Build & Test
```bash
cd /home/ebok/pitchmatter/capshield-staking-contract
forge build          # Compile contracts → out/ directory
forge test           # Run tests in test/ (currently empty)
forge fmt            # Format all .sol files to Foundry standard
forge snapshot       # Generate gas snapshot
```

### Configuration
- **foundry.toml**: Default profile: src="src", out="out", libs=["lib"]
- **src/CAPXStaking.sol**: Single contract, 436 lines
- **lib/forge-std**: Standard testing library imported but not used yet

## Testing Strategy (To Be Implemented)
Expected test structure:
- Stake/unstake flow for each lock option
- Reward calculation verification (APR * elapsed time)
- Lock period enforcement
- One-position-per-user constraint
- Pause/unpause behavior
- Owner-only functions protection
- Edge cases: zero APR, maximum lock multiplier, reward pool depletion

## Common Implementation Tasks

### Adding New Features
1. Update `Position` struct if storing per-user data
2. Add event definition near Events section
3. Implement function with proper guards: `external nonReentrant whenNotPaused`
4. Emit events with all relevant data for indexing
5. Include JSDoc comments with @param/@return/@dev

### Modifying Reward Logic
1. Change `baseAprBps` setter in `setBaseAprBps()`
2. Update lock multipliers via `setLockMultiplierBps()`
3. Verify impact on `_claimableRewardView()` calculation
4. **Never modify SECONDS_PER_YEAR** or reward formula denominator—maintains backward compatibility

### Owner/Admin Functions
- Protected by `onlyOwner` modifier (inherited from Ownable)
- Use `nonReentrant` for state-modifying calls
- Include clear event emission for auditability
- Multisig owner enforced; no EOA deployments allowed

## Key Dependencies & Imports
- **OpenZeppelin**: IERC20, SafeERC20, Ownable, ReentrancyGuard, Pausable
- **Solidity 0.8.30**: Uses newer syntax (no SafeMath needed)
- **forge-std**: Available but minimal usage in current codebase

## File References
- [src/CAPXStaking.sol](../src/CAPXStaking.sol) – Main contract (~436 lines)
- [foundry.toml](../foundry.toml) – Build configuration
- [README.md](../README.md) – Foundry setup guide

## Notes for AI Agents
- Contract is **production-ready** but lacks formal tests—prioritize test coverage for changes
- **No test files exist yet** (test/ directory is empty)
- **No script files exist** (script/ directory is empty)
- Position struct uses `uint128/uint64` for packing—preserve bit sizes when modifying
- **Reward pool is finite**: If rewards accrued exceed available balance, claims fail with `InsufficientRewards()`
