// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CAPXStaking
 * @notice Single-position staking contract for CAPX with optional lock durations and CAPX-only rewards.
 *
 * @dev Key rules:
 * - Rewards are paid from a pre-funded reward pool (owner deposits CAPX in advance).
 * - Contract is expected to be fee-exempt/whitelisted in CAPX so transfers are not taxed.
 * - Each address can have only ONE active position at a time.
 * - Users cannot change their position configuration after staking (no adding to stake, no lock changes).
 * - Users can claim rewards anytime, even before unlock.
 * - Users can compound rewards on-chain via `compound()` which internally increases their staked amount without transferrinng tokens to the user.
 * - Pausing disables ALL activity: stake, claim, compound, and unstake.
 * - Owner must be a multisig contract (enforced in constructor).
 */
contract CAPXStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ----------------------------
    // Constants
    // ----------------------------

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ----------------------------
    // Types
    // ----------------------------

    /**
     * @notice Supported staking lock options.
     */
    enum LockOption {
        FLEX, // no lock
        DAYS_30,
        DAYS_90,
        DAYS_180
    }

    /**
     * @notice Single staking position per user.
     */
    struct Position {
        uint128 amount; // staked principal
        uint64 unlockTime; // principal withdraw allowed after this time (0 for FLEX)
        uint64 lastClaimTime; // last time rewards were claimed/compounded
        LockOption lockOption; // chosen lock option
        bool active; // true if position exists and not withdrawn
    }

    // ----------------------------
    // State
    // ----------------------------

    IERC20 public immutable capx;

    uint256 public totalStaked;

    // Base APR in basis points (default: 1200 = 12.00%)
    uint256 public baseAprBps;

    // Minimum stake amount (default: 1000 CAPX)
    uint256 public minStakeAmount;

    /**
     * @dev Lock multipliers in basis points.
     * Final APR = baseAprBps * multiplierBps / 10_000
     */
    mapping(LockOption => uint256) public lockMultiplierBps;

    // One position per lock option per address (up to 4 positions per user)
    mapping(address => mapping(LockOption => Position)) private userPositions;

    // ----------------------------
    // Events
    // ----------------------------

    event Staked(
        address indexed user,
        uint256 amount,
        LockOption lockOption,
        uint256 unlockTime
    );
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event Compounded(address indexed user, uint256 rewardAdded);
    event RewardsDeposited(address indexed from, uint256 amount);

    event BaseAprUpdated(uint256 oldAprBps, uint256 newAprBps);
    event MinStakeAmountUpdated(uint256 oldMinStake, uint256 newMinStake);
    event LockMultiplierUpdated(
        LockOption indexed lockOption,
        uint256 oldMultiplierBps,
        uint256 newMultiplierBps
    );

    event TokenRecovered(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    // ----------------------------
    // Errors
    // ----------------------------

    error ZeroAddress();
    error AdminMustBeContract();
    error InvalidAmount();
    error InvalidRate();
    error PositionExists();
    error NoActivePosition();
    error StillLocked();
    error InsufficientRewards();
    error CannotRecoverCAPX();

    // ----------------------------
    // Constructor
    // ----------------------------

    /**
     * @notice Deploy staking contract.
     * @param admin Multisig owner address (must be a contract).
     * @param capxToken CAPX token address.
     */
    constructor(address admin, address capxToken) Ownable(admin) {
        if (admin == address(0) || capxToken == address(0))
            revert ZeroAddress();
        if (!_isContract(admin)) revert AdminMustBeContract();

        capx = IERC20(capxToken);

        // Defaults requested
        baseAprBps = 1200; // 12%
        minStakeAmount = 1000e18;

        // Default multipliers
        lockMultiplierBps[LockOption.FLEX] = 10_000; // 1.00x
        lockMultiplierBps[LockOption.DAYS_30] = 12_500; // 1.25x
        lockMultiplierBps[LockOption.DAYS_90] = 15_000; // 1.50x
        lockMultiplierBps[LockOption.DAYS_180] = 20_000; // 2.00x
    }

    // ----------------------------
    // User Actions
    // ----------------------------

    /**
     * @notice Stake CAPX with a chosen lock option.
     * @dev Only one active position allowed per lock option per address.
     * @param amount Amount of CAPX to stake.
     * @param lockOption FLEX / 30d / 90d / 180d.
     */
    function stake(
        uint256 amount,
        LockOption lockOption
    ) external nonReentrant whenNotPaused {
        if (amount < minStakeAmount) revert InvalidAmount();

        Position storage p = userPositions[msg.sender][lockOption];
        if (p.active) revert PositionExists();

        uint256 unlockTime = block.timestamp + _lockDuration(lockOption);

        userPositions[msg.sender][lockOption] = Position({
            amount: uint128(amount),
            unlockTime: uint64(unlockTime),
            lastClaimTime: uint64(block.timestamp),
            lockOption: lockOption,
            active: true
        });

        totalStaked += amount;
        capx.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockOption, unlockTime);
    }

    /**
     * @notice Claim accrued CAPX rewards anytime (even before unlock).
     * @dev Claiming early supports manual compounding by re-staking rewards.
     * @param lockOption The lock option for the position to claim from.
     */
    function claim(LockOption lockOption) external nonReentrant whenNotPaused {
        Position storage p = userPositions[msg.sender][lockOption];
        if (!p.active) revert NoActivePosition();

        uint256 reward = _claimableReward(p);
        if (reward == 0) return;

        if (reward > _availableRewards()) revert InsufficientRewards();

        p.lastClaimTime = uint64(block.timestamp);
        capx.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @notice Compound accrued rewards into the staked amount.
     * @dev This increases principal without transferring tokens to the user.
     *      Works even during lock period.
     * @param lockOption The lock option for the position to compound.
     */
    function compound(
        LockOption lockOption
    ) external nonReentrant whenNotPaused {
        Position storage p = userPositions[msg.sender][lockOption];
        if (!p.active) revert NoActivePosition();

        uint256 reward = _claimableReward(p);
        if (reward == 0) return;

        if (reward > _availableRewards()) revert InsufficientRewards();

        p.lastClaimTime = uint64(block.timestamp);

        // Add rewards to principal
        p.amount = uint128(uint256(p.amount) + reward);
        totalStaked += reward;

        emit Compounded(msg.sender, reward);
    }

    /**
     * @notice Unstake principal. Locked positions can only unstake after unlock.
     * @dev FLEX positions can unstake anytime.
     * @param lockOption The lock option for the position to unstake.
     */
    function unstake(LockOption lockOption) external nonReentrant {
        Position storage p = userPositions[msg.sender][lockOption];
        if (!p.active) revert NoActivePosition();

        if (block.timestamp < p.unlockTime) revert StillLocked();

        uint256 amount = p.amount;
        uint256 reward = _claimableReward(p);
        if (reward > _availableRewards()) revert InsufficientRewards();

        // Clear position first
        delete userPositions[msg.sender][lockOption];

        totalStaked -= amount;
        capx.safeTransfer(msg.sender, amount + reward);

        emit RewardClaimed(msg.sender, reward);
        emit Unstaked(msg.sender, amount);
    }

    // ----------------------------
    // Admin Actions
    // ----------------------------

    /**
     * @notice Deposit CAPX into the reward pool.
     * @dev Rewards are paid from: capx.balanceOf(this) - totalStaked.
     * @param amount Amount of CAPX to deposit as rewards.
     */
    function depositRewards(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        capx.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsDeposited(msg.sender, amount);
    }

    /**
     * @notice Update the base APR (in basis points).
     * @param newBaseAprBps New base APR in bps (e.g., 1200 = 12%).
     */
    function setBaseAprBps(uint256 newBaseAprBps) external onlyOwner {
        // Keep sane bounds: 0% to 100% base APR
        if (newBaseAprBps > BPS_DENOMINATOR) revert InvalidRate();

        uint256 old = baseAprBps;
        baseAprBps = newBaseAprBps;

        emit BaseAprUpdated(old, newBaseAprBps);
    }

    /**
     * @notice Update minimum stake amount.
     * @param newMinStakeAmount New minimum stake amount in CAPX.
     */
    function setMinStakeAmount(uint256 newMinStakeAmount) external onlyOwner {
        if (newMinStakeAmount == 0) revert InvalidAmount();

        uint256 old = minStakeAmount;
        minStakeAmount = newMinStakeAmount;

        emit MinStakeAmountUpdated(old, newMinStakeAmount);
    }

    /**
     * @notice Update lock multiplier for a lock option.
     * @param lockOption Lock option.
     * @param newMultiplierBps New multiplier in bps (10_000 = 1.00x).
     */
    function setLockMultiplierBps(
        LockOption lockOption,
        uint256 newMultiplierBps
    ) external onlyOwner {
        if (newMultiplierBps < 10_000) revert InvalidRate();

        uint256 old = lockMultiplierBps[lockOption];
        lockMultiplierBps[lockOption] = newMultiplierBps;

        emit LockMultiplierUpdated(lockOption, old, newMultiplierBps);
    }

    /**
     * @notice Pause all staking activity (stake/unstake/claim/compound).
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause all staking activity.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Recover non-CAPX tokens accidentally sent to this contract.
     * @dev CAPX recovery is disabled to avoid affecting user funds and reward accounting.
     * @param token Token address to recover.
     * @param to Receiver address.
     * @param amount Amount to recover.
     */
    function recoverToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (token == address(capx)) revert CannotRecoverCAPX();

        IERC20(token).safeTransfer(to, amount);
        emit TokenRecovered(token, to, amount);
    }

    // ----------------------------
    // Views (Frontend-friendly)
    // ----------------------------

    /**
     * @notice Returns the user's staking position for a specific lock option.
     * @param user Address of the user.
     * @param lockOption The lock option to retrieve.
     */
    function getPosition(
        address user,
        LockOption lockOption
    ) external view returns (Position memory) {
        return userPositions[user][lockOption];
    }

    /**
     * @notice Returns all 4 staking positions for a user (FLEX, 30d, 90d, 180d).
     * @param user Address of the user.
     * @return positions Array of 4 Position structs in lock option order.
     */
    function getAllPositions(
        address user
    ) external view returns (Position[4] memory) {
        return
            [
                userPositions[user][LockOption.FLEX],
                userPositions[user][LockOption.DAYS_30],
                userPositions[user][LockOption.DAYS_90],
                userPositions[user][LockOption.DAYS_180]
            ];
    }

    /**
     * @notice Returns the claimable reward for a specific position at current timestamp.
     * @param user Address of the user.
     * @param lockOption The lock option to check.
     */
    function claimable(
        address user,
        LockOption lockOption
    ) external view returns (uint256) {
        Position memory p = userPositions[user][lockOption];
        if (!p.active || p.amount == 0) return 0;
        return _claimableRewardView(p);
    }

    /**
     * @notice Returns total claimable rewards across all user positions.
     * @param user Address of the user.
     */
    function totalClaimable(address user) external view returns (uint256) {
        uint256 total = 0;
        total += _claimableRewardView(userPositions[user][LockOption.FLEX]);
        total += _claimableRewardView(userPositions[user][LockOption.DAYS_30]);
        total += _claimableRewardView(userPositions[user][LockOption.DAYS_90]);
        total += _claimableRewardView(userPositions[user][LockOption.DAYS_180]);
        return total;
    }

    /**
     * @notice Returns the available reward pool balance (excludes staked principal).
     */
    function availableRewards() external view returns (uint256) {
        return _availableRewards();
    }

    /**
     * @notice Returns the effective APR (bps) for a lock option.
     */
    function effectiveAprBps(
        LockOption lockOption
    ) external view returns (uint256) {
        return (baseAprBps * lockMultiplierBps[lockOption]) / BPS_DENOMINATOR;
    }

    // ----------------------------
    // Internal
    // ----------------------------

    function _lockDuration(
        LockOption lockOption
    ) internal pure returns (uint256) {
        if (lockOption == LockOption.FLEX) return 0;
        if (lockOption == LockOption.DAYS_30) return 30 days;
        if (lockOption == LockOption.DAYS_90) return 90 days;
        if (lockOption == LockOption.DAYS_180) return 180 days;
        return 0;
    }

    function _claimableReward(
        Position storage p
    ) internal view returns (uint256) {
        Position memory copy = p;
        return _claimableRewardView(copy);
    }

    function _claimableRewardView(
        Position memory p
    ) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - uint256(p.lastClaimTime);
        if (elapsed == 0) return 0;

        uint256 multiplier = lockMultiplierBps[p.lockOption];
        uint256 aprBps = (baseAprBps * multiplier) / BPS_DENOMINATOR;

        // reward = amount * apr * elapsed / year
        return
            (uint256(p.amount) * aprBps * elapsed) /
            (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    function _availableRewards() internal view returns (uint256) {
        uint256 bal = capx.balanceOf(address(this));
        if (bal <= totalStaked) return 0;
        return bal - totalStaked;
    }

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
