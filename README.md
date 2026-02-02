# CAPXStaking Contract

A multi-position ERC20 staking contract for CAPX tokens with flexible lock options and APR-based rewards.

## Overview

**CAPXStaking** allows users to stake CAPX tokens with optional lock durations (FLEX, 30d, 90d, 180d) and earn rewards based on a configurable APR. Key features:

- **One position per lock option** – Users can maintain up to 4 simultaneous positions (one per lock duration)
- **Flexible or locked staking** – FLEX positions unlock immediately; locked positions enforce time-lock
- **APR with multipliers** – Base APR boosted by lock-duration multiplier (1.0x to 2.0x)
- **Manual compounding** – Claim rewards or compound them into principal without token transfer
- **Pauseable** – Owner can pause stake/claim/compound operations (unstaking remains available for emergencies to preserve decentralization)
- **Multisig-enforced** – Owner must be a contract (enforced in constructor)

## Installation

### Prerequisites
- [Foundry](https://getfoundry.sh/) (forge, cast, anvil)

### Setup

```bash
# Clone repository
cd /path/to/capshield-staking-contract

# Install dependencies
forge install openzeppelin/openzeppelin-contracts
forge install vectorized/solady

# Build contracts
forge build
```

## Usage

### Build
```bash
forge build
```

### Test
```bash
# Run all tests
forge test

# Run specific test
forge test --match test_name_of_test

# With verbosity
forge test -vv
```

### Format
```bash
forge fmt
```

### Gas Snapshots
```bash
forge snapshot
```


## Contract Architecture

### Core Components

**CAPXStaking** ([src/CAPXStaking.sol](src/CAPXStaking.sol))
- Main staking contract managing user positions and rewards
- Single-entry point for all staking operations
- Immutable CAPX token reference

**CAPX Token** ([test/mocks/CAPX.sol](test/mocks/CAPX.sol))
- ERC20 token with role-based minting
- Fee-on-transfer with exemptions for treasury/DAO
- Used for mocking in tests and as actual reward token

### Data Structures

```solidity
enum LockOption {
    FLEX,        // 0 days - no lock
    DAYS_30,     // 30 days
    DAYS_90,     // 90 days
    DAYS_180     // 180 days
}

struct Position {
    uint128 amount;          // staked principal
    uint64 unlockTime;       // principal withdrawable after this timestamp
    uint64 lastClaimTime;    // last reward claim/compound time
    LockOption lockOption;   // chosen lock duration
    bool active;             // position exists and not withdrawn
}
```

### Key Functions

#### User Functions

| Function | Description |
|----------|-------------|
| `stake(uint256 amount, LockOption lockOption)` | Stake CAPX for a specific lock duration |
| `claim(LockOption lockOption)` | Claim accrued rewards without unstaking |
| `compound(LockOption lockOption)` | Add rewards to principal (no token transfer) |
| `unstake(LockOption lockOption)` | Withdraw principal + rewards (auto-claims) |

#### Admin Functions

| Function | Description |
|----------|-------------|
| `setBaseAprBps(uint256 newBaseAprBps)` | Update base APR (in basis points) |
| `setLockMultiplierBps(LockOption, uint256)` | Update lock-duration multiplier |
| `setMinStakeAmount(uint256)` | Update minimum stake amount |
| `depositRewards(uint256 amount)` | Add CAPX to reward pool |
| `pause() / unpause()` | Pause/resume stake/claim/compound (unstaking always available) |

#### View Functions

| Function | Returns |
|----------|---------|
| `getPosition(address, LockOption)` | Single position data |
| `getAllPositions(address)` | All 4 positions for a user |
| `claimable(address, LockOption)` | Pending rewards for a position |
| `totalClaimable(address)` | Total rewards across all positions |
| `availableRewards()` | Reward pool balance |
| `effectiveAprBps(LockOption)` | Final APR including multiplier |

## Reward Calculation

Rewards accrue based on elapsed time since last claim:

```
reward = amount × (baseAprBps × lockMultiplier / 10,000) × elapsed / SECONDS_PER_YEAR
```

- **baseAprBps** – Default: 1200 (12% per year)
- **lockMultiplier** – FLEX: 1.0x, 30d: 1.25x, 90d: 1.5x, 180d: 2.0x
- **elapsed** – Seconds since `lastClaimTime`
- **SECONDS_PER_YEAR** – 365 days (31,536,000 seconds)


## Configuration

Default values:
- **baseAprBps** – 1200 (12%)
- **minStakeAmount** – 1000 CAPX
- **Lock multipliers** – FLEX: 1.0x, 30d: 1.25x, 90d: 1.5x, 180d: 2.0x

Update via owner functions (see Admin Functions above).

## Important Notes

### Constraints

1. **One position per lock option** – Cannot have two FLEX positions simultaneously
2. **Immutable CAPX token** – Cannot be recovered; prevents fund loss
3. **Finite reward pool** – If rewards accrued exceed available balance, claims fail with `InsufficientRewards()`
4. **Fee-exempt requirement** – CAPX should whitelist this contract to avoid transfer taxes
5. **Multisig-only owner** – Contract enforces owner is a contract (no EOA deployments)

### Gas Optimization

- Uses `uint128/uint64` struct packing for position storage
- Custom errors instead of revert strings
- Inline reward calculation (no external calls)
- View functions allow free computation (no state changes)

### Security Considerations

- ReentrancyGuard on all state-modifying functions
- Pausable mechanism for emergency stops
- Zero-address validation on all admin operations
- Time-lock enforcement prevents early unstaking