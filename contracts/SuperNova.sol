/*
SuperNova

This implements the core SuperNova contract, which allows for generalized
staking, yield farming, and token distribution. This also implements
the POLAR spending mechanic for boosted reward distribution.

SPDX-License-Identifier: MIT
*/

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./ISuperNova.sol";
import "./SuperNovaPool.sol";
import "./MathUtils.sol";

/**
 * @title SuperNova
 */
contract SuperNova is ISuperNova, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using MathUtils for int128;

    // single stake by user
    struct Stake {
        uint256 shares;
        uint256 timestamp;
    }

    // summary of total user stake/shares
    struct User {
        uint256 shares;
        uint256 shareSeconds;
        uint256 lastUpdated;
    }

    // single funding/reward schedule
    struct Funding {
        uint256 amount;
        uint256 shares;
        uint256 unlocked;
        uint256 lastUpdated;
        uint256 start;
        uint256 end;
        uint256 duration;
    }

    // constants
    uint256 public constant BONUS_DECIMALS = 18;
    uint256 public constant INITIAL_SHARES_PER_TOKEN = 10**6;
    uint256 public constant MAX_ACTIVE_FUNDINGS = 16;

    // token pool fields
    SuperNovaPool private immutable _stakingPool;
    SuperNovaPool private immutable _unlockedPool;
    SuperNovaPool private immutable _lockedPool;
    Funding[] public fundings;

    // user staking fields
    mapping(address => User) public userTotals;
    mapping(address => Stake[]) public userStakes;

    // time bonus fields
    uint256 public immutable bonusMin;
    uint256 public immutable bonusMax;
    uint256 public immutable bonusPeriod;

    // global state fields
    uint256 public totalLockedShares;
    uint256 public totalStakingShares;
    uint256 public totalRewards;
    uint256 public totalPolarRewards;
    uint256 public totalStakingShareSeconds;
    uint256 public lastUpdated;

    // polar fields
    IERC20 private immutable _polar;

    /**
     * @param stakingToken_ the token that will be staked
     * @param rewardToken_ the token distributed to users as they unstake
     * @param bonusMin_ initial time bonus
     * @param bonusMax_ maximum time bonus
     * @param bonusPeriod_ period (in seconds) over which time bonus grows to max
     * @param polar_ address for Polar token
     */
    constructor(
        address stakingToken_,
        address rewardToken_,
        uint256 bonusMin_,
        uint256 bonusMax_,
        uint256 bonusPeriod_,
        address polar_
    ) public {
        require(
            bonusMin_ <= bonusMax_,
            "SuperNova: initial time bonus greater than max"
        );

        _stakingPool = new SuperNovaPool(stakingToken_);
        _unlockedPool = new SuperNovaPool(rewardToken_);
        _lockedPool = new SuperNovaPool(rewardToken_);

        bonusMin = bonusMin_;
        bonusMax = bonusMax_;
        bonusPeriod = bonusPeriod_;

        _polar = IERC20(polar_);

        lastUpdated = block.timestamp;
    }

    // IStaking

    /**
     * @inheritdoc IStaking
     */
    function stake(uint256 amount, bytes calldata) external override {
        _stake(msg.sender, msg.sender, amount);
    }

    /**
     * @inheritdoc IStaking
     */
    function stakeFor(
        address user,
        uint256 amount,
        bytes calldata
    ) external override {
        _stake(msg.sender, user, amount);
    }

    /**
     * @inheritdoc IStaking
     */
    function unstake(uint256 amount, bytes calldata) external override {
        _unstake(amount, 0);
    }

    /**
     * @inheritdoc IStaking
     */
    function totalStakedFor(address addr)
        public
        override
        view
        returns (uint256)
    {
        if (totalStakingShares == 0) {
            return 0;
        }
        return
            totalStaked().mul(userTotals[addr].shares).div(totalStakingShares);
    }

    /**
     * @inheritdoc IStaking
     */
    function totalStaked() public override view returns (uint256) {
        return _stakingPool.balance();
    }

    /**
     * @inheritdoc IStaking
     * @dev redundant with stakingToken() in order to implement IStaking (EIP-900)
     */
    function token() external override view returns (address) {
        return address(_stakingPool.token());
    }

    // ISuperNova

    /**
     * @inheritdoc ISuperNova
     */
    function stakingToken() public override view returns (address) {
        return address(_stakingPool.token());
    }

    /**
     * @inheritdoc ISuperNova
     */
    function rewardToken() public override view returns (address) {
        return address(_unlockedPool.token());
    }

    /**
     * @inheritdoc ISuperNova
     */
    function fund(uint256 amount, uint256 duration) public override {
        fund(amount, duration, block.timestamp);
    }

    /**
     * @inheritdoc ISuperNova
     */
    function fund(
        uint256 amount,
        uint256 duration,
        uint256 start
    ) public override onlyOwner {
        // validate
        require(amount > 0, "SuperNova: funding amount is zero");
        require(start >= block.timestamp, "SuperNova: funding start is past");
        require(
            fundings.length < MAX_ACTIVE_FUNDINGS,
            "SuperNova: exceeds max active funding schedules"
        );

        // update bookkeeping
        _update(msg.sender);

        // mint shares at current rate
        uint256 lockedTokens = totalLocked();
        uint256 mintedLockedShares = (lockedTokens > 0)
            ? totalLockedShares.mul(amount).div(lockedTokens)
            : amount.mul(INITIAL_SHARES_PER_TOKEN);

        totalLockedShares = totalLockedShares.add(mintedLockedShares);

        // create new funding
        fundings.push(
            Funding({
                amount: amount,
                shares: mintedLockedShares,
                unlocked: 0,
                lastUpdated: start,
                start: start,
                end: start.add(duration),
                duration: duration
            })
        );

        // do transfer of funding
        _lockedPool.token().safeTransferFrom(
            msg.sender,
            address(_lockedPool),
            amount
        );
        emit RewardsFunded(amount, duration, start, totalLocked());
    }

    /**
     * @inheritdoc ISuperNova
     */
    function withdraw(uint256 amount) external override onlyOwner {
        require(amount > 0, "SuperNova: withdraw amount is zero");
        require(
            amount <= _polar.balanceOf(address(this)),
            "SuperNova: withdraw amount exceeds balance"
        );
        // do transfer
        //Burn Half tokens and half transfer to owner address
        uint256 burnedToken = amount.div(2);
        _polar.safeTransfer(address(1), burnedToken);
        _polar.safeTransfer(msg.sender, burnedToken);

        emit PolarWithdrawn(amount);
    }

    /**
     * @inheritdoc ISuperNova
     */
    function unstake(
        uint256 amount,
        uint256 polar,
        bytes calldata
    ) external override {
        _unstake(amount, polar);
    }

    /**
     * @inheritdoc ISuperNova
     */
    function update() external override nonReentrant {
        _update(msg.sender);
    }

    /**
     * @inheritdoc ISuperNova
     */
    function clean() external override onlyOwner {
        // update bookkeeping
        _update(msg.sender);

        // check for stale funding schedules to expire
        uint256 removed = 0;
        uint256 originalSize = fundings.length;
        for (uint256 i = 0; i < originalSize; i++) {
            Funding storage funding = fundings[i.sub(removed)];
            uint256 idx = i.sub(removed);

            if (_unlockable(idx) == 0 && block.timestamp >= funding.end) {
                emit RewardsExpired(
                    funding.amount,
                    funding.duration,
                    funding.start
                );

                // remove at idx by copying last element here, then popping off last
                // (we don't care about order)
                fundings[idx] = fundings[fundings.length.sub(1)];
                fundings.pop();
                removed = removed.add(1);
            }
        }
    }

    // SuperNova

    /**
     * @dev internal implementation of staking methods
     * @param staker address to do deposit of staking tokens
     * @param beneficiary address to gain credit for this stake operation
     * @param amount number of staking tokens to deposit
     */
    function _stake(
        address staker,
        address beneficiary,
        uint256 amount
    ) private nonReentrant {
        // validate
        require(amount > 0, "SuperNova: stake amount is zero");
        require(
            beneficiary != address(0),
            "Supernova: beneficiary is zero address"
        );

        // mint staking shares at current rate
        uint256 mintedStakingShares = (totalStakingShares > 0)
            ? totalStakingShares.mul(amount).div(totalStaked())
            : amount.mul(INITIAL_SHARES_PER_TOKEN);
        require(mintedStakingShares > 0, "SuperNova: stake amount too small");

        // update bookkeeping
        _update(beneficiary);

        // update user staking info
        User storage user = userTotals[beneficiary];
        user.shares = user.shares.add(mintedStakingShares);
        user.lastUpdated = block.timestamp;

        userStakes[beneficiary].push(
            Stake(mintedStakingShares, block.timestamp)
        );

        // add newly minted shares to global total
        totalStakingShares = totalStakingShares.add(mintedStakingShares);

        // transactions
        _stakingPool.token().safeTransferFrom(
            staker,
            address(_stakingPool),
            amount
        );

        emit Staked(beneficiary, amount, totalStakedFor(beneficiary), "");
    }

    /**
     * @dev internal implementation of unstaking methods
     * @param amount number of tokens to unstake
     * @param polar number of POLAR tokens applied to unstaking operation
     * @return number of reward tokens distributed
     */
    function _unstake(uint256 amount, uint256 polar)
        private
        nonReentrant
        returns (uint256)
    {
        // validate
        require(amount > 0, "SuperNova: unstake amount is zero");
        require(
            totalStakedFor(msg.sender) >= amount,
            "Supernova: unstake amount exceeds balance"
        );

        // update bookkeeping
        _update(msg.sender);

        // do unstaking, first-in last-out, respecting time bonus
        uint256 timeWeightedShareSeconds = _unstakeFirstInLastOut(amount);

        // compute and apply POLAR token bonus
        uint256 polarWeightedShareSeconds = polarBonus(polar)
            .mul(timeWeightedShareSeconds)
            .div(10**BONUS_DECIMALS);

        uint256 rewardAmount = totalUnlocked()
            .mul(polarWeightedShareSeconds)
            .div(totalStakingShareSeconds.add(polarWeightedShareSeconds));

        // update global stats for distributions
        if (polar > 0) {
            totalPolarRewards = totalPolarRewards.add(rewardAmount);
        }
        totalRewards = totalRewards.add(rewardAmount);

        // transactions
        _stakingPool.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount, totalStakedFor(msg.sender), "");
        if (rewardAmount > 0) {
            _unlockedPool.transfer(msg.sender, rewardAmount);
            emit RewardsDistributed(msg.sender, rewardAmount);
        }
        if (polar > 0) {
            _polar.safeTransferFrom(msg.sender, address(this), polar);
            emit PolarSpent(msg.sender, polar);
        }
        return rewardAmount;
    }

    /**
     * @dev helper function to actually execute unstaking, first-in last-out, 
     while computing and applying time bonus. This function also updates
     user and global totals for shares and share-seconds.
     * @param amount number of staking tokens to withdraw
     * @return time bonus weighted staking share seconds
     */
    function _unstakeFirstInLastOut(uint256 amount) private returns (uint256) {
        uint256 stakingSharesToBurn = totalStakingShares.mul(amount).div(
            totalStaked()
        );
        require(stakingSharesToBurn > 0, "Supernova: unstake amount too small");

        // redeem from most recent stake and go backwards in time.
        uint256 shareSecondsToBurn = 0;
        uint256 sharesLeftToBurn = stakingSharesToBurn;
        uint256 bonusWeightedShareSeconds = 0;
        Stake[] storage stakes = userStakes[msg.sender];
        while (sharesLeftToBurn > 0) {
            Stake storage lastStake = stakes[stakes.length - 1];
            uint256 stakeTime = block.timestamp.sub(lastStake.timestamp);

            uint256 bonus = timeBonus(stakeTime);

            if (lastStake.shares <= sharesLeftToBurn) {
                // fully redeem a past stake
                bonusWeightedShareSeconds = bonusWeightedShareSeconds.add(
                    lastStake.shares.mul(stakeTime).mul(bonus).div(
                        10**BONUS_DECIMALS
                    )
                );
                shareSecondsToBurn = shareSecondsToBurn.add(
                    lastStake.shares.mul(stakeTime)
                );
                sharesLeftToBurn = sharesLeftToBurn.sub(lastStake.shares);
                stakes.pop();
            } else {
                // partially redeem a past stake
                bonusWeightedShareSeconds = bonusWeightedShareSeconds.add(
                    sharesLeftToBurn.mul(stakeTime).mul(bonus).div(
                        10**BONUS_DECIMALS
                    )
                );
                shareSecondsToBurn = shareSecondsToBurn.add(
                    sharesLeftToBurn.mul(stakeTime)
                );
                lastStake.shares = lastStake.shares.sub(sharesLeftToBurn);
                sharesLeftToBurn = 0;
            }
        }
        // update user totals
        User storage user = userTotals[msg.sender];
        user.shareSeconds = user.shareSeconds.sub(shareSecondsToBurn);
        user.shares = user.shares.sub(stakingSharesToBurn);
        user.lastUpdated = block.timestamp;

        // update global totals
        totalStakingShareSeconds = totalStakingShareSeconds.sub(
            shareSecondsToBurn
        );
        totalStakingShares = totalStakingShares.sub(stakingSharesToBurn);

        return bonusWeightedShareSeconds;
    }

    /**
     * @dev internal implementation of update method
     * @param addr address for user accounting update
     */
    function _update(address addr) private {
        _unlockTokens();

        // global accounting
        uint256 deltaTotalShareSeconds = (block.timestamp.sub(lastUpdated)).mul(
            totalStakingShares
        );
        totalStakingShareSeconds = totalStakingShareSeconds.add(
            deltaTotalShareSeconds
        );
        lastUpdated = block.timestamp;

        // user accounting
        User storage user = userTotals[addr];
        uint256 deltaUserShareSeconds = (block.timestamp.sub(user.lastUpdated))
            .mul(user.shares);
        user.shareSeconds = user.shareSeconds.add(deltaUserShareSeconds);
        user.lastUpdated = block.timestamp;
    }

    /**
     * @dev unlocks reward tokens based on funding schedules
     */
    function _unlockTokens() private {
        uint256 tokensToUnlock = 0;
        uint256 lockedTokens = totalLocked();

        if (totalLockedShares == 0) {
            // handle any leftover
            tokensToUnlock = lockedTokens;
        } else {
            // normal case: unlock some shares from each funding schedule
            uint256 sharesToUnlock = 0;
            for (uint256 i = 0; i < fundings.length; i++) {
                uint256 shares = _unlockable(i);
                Funding storage funding = fundings[i];
                if (shares > 0) {
                    funding.unlocked = funding.unlocked.add(shares);
                    funding.lastUpdated = block.timestamp;
                    sharesToUnlock = sharesToUnlock.add(shares);
                }
            }
            tokensToUnlock = sharesToUnlock.mul(lockedTokens).div(
                totalLockedShares
            );
            totalLockedShares = totalLockedShares.sub(sharesToUnlock);
        }

        if (tokensToUnlock > 0) {
            _lockedPool.transfer(address(_unlockedPool), tokensToUnlock);
            emit RewardsUnlocked(tokensToUnlock, totalUnlocked());
        }
    }

    /**
     * @dev helper function to compute updates to funding schedules
     * @param idx index of the funding
     * @return the number of unlockable shares
     */
    function _unlockable(uint256 idx) private view returns (uint256) {
        Funding storage funding = fundings[idx];

        // funding schedule is in future
        if (block.timestamp < funding.start) {
            return 0;
        }
        // empty
        if (funding.unlocked >= funding.shares) {
            return 0;
        }
        // handle zero-duration period or leftover dust from integer division
        if (block.timestamp >= funding.end) {
            return funding.shares.sub(funding.unlocked);
        }

        return
            (block.timestamp.sub(funding.lastUpdated)).mul(funding.shares).div(
                funding.duration
            );
    }

    /**
     * @notice compute time bonus earned as a function of staking time
     * @param time length of time for which the tokens have been staked
     * @return bonus multiplier for time
     */
    function timeBonus(uint256 time) public view returns (uint256) {
        if (time >= bonusPeriod) {
            return uint256(10**BONUS_DECIMALS).add(bonusMax);
        }

        // linearly interpolate between bonus min and bonus max
        uint256 bonus = bonusMin.add(
            (bonusMax.sub(bonusMin)).mul(time).div(bonusPeriod)
        );
        return uint256(10**BONUS_DECIMALS).add(bonus);
    }

    /**
     * @notice compute POLAR bonus as a function of usage ratio and POLAR spent
     * @param polar number of POLAR token applied to bonus
     * @return multiplier value
     */
    function polarBonus(uint256 polar) public view returns (uint256) {
        if (polar == 0) {
            return 10**BONUS_DECIMALS;
        }
        require(
            polar >= 10**BONUS_DECIMALS,
            "SUPERNOVA: POLAR amount is between 0 and 1"
        );

        uint256 buffer = uint256(10**(BONUS_DECIMALS - 2)); // 0.01
        uint256 r = ratio().add(buffer);
        uint256 x = polar.add(buffer);

        return
            uint256(10**BONUS_DECIMALS).add(
                uint256(int128(x.mul(2**64).div(r)).logbase10())
                    .mul(10**BONUS_DECIMALS)
                    .div(2**64)
            );
    }

    /**
     * @return portion of rewards which have been boosted by POLAR token
     */
    function ratio() public view returns (uint256) {
        if (totalRewards == 0) {
            return 0;
        }
        return totalPolarRewards.mul(10**BONUS_DECIMALS).div(totalRewards);
    }

    // SuperNova -- informational functions

    /**
     * @return total number of locked reward tokens
     */
    function totalLocked() public view returns (uint256) {
        return _lockedPool.balance();
    }

    /**
     * @return total number of unlocked reward tokens
     */
    function totalUnlocked() public view returns (uint256) {
        return _unlockedPool.balance();
    }

    /**
     * @return number of active funding schedules
     */
    function fundingCount() public view returns (uint256) {
        return fundings.length;
    }

    /**
     * @param addr address of interest
     * @return number of active stakes for user
     */
    function stakeCount(address addr) public view returns (uint256) {
        return userStakes[addr].length;
    }

    /**
     * @notice preview estimated reward distribution for full unstake with no POLAR applied
     * @return estimated reward
     * @return estimated overall multiplier
     * @return estimated raw user share seconds that would be burned
     * @return estimated total unlocked rewards
     */
    function preview()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return preview(msg.sender, totalStakedFor(msg.sender), 0);
    }

    /**
     * @notice preview estimated reward distribution for unstaking
     * @param addr address of interest for preview
     * @param amount number of tokens that would be unstaked
     * @param polar number of POLAR tokens that would be applied
     * @return estimated reward
     * @return estimated overall multiplier
     * @return estimated raw user share seconds that would be burned
     * @return estimated total unlocked rewards
     */
    function preview(
        address addr,
        uint256 amount,
        uint256 polar
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        // compute expected updates to global totals
        uint256 deltaUnlocked = 0;
        if (totalLockedShares != 0) {
            uint256 sharesToUnlock = 0;
            for (uint256 i = 0; i < fundings.length; i++) {
                sharesToUnlock = sharesToUnlock.add(_unlockable(i));
            }
            deltaUnlocked = sharesToUnlock.mul(totalLocked()).div(
                totalLockedShares
            );
        }

        // no need for unstaking/rewards computation
        if (amount == 0) {
            return (0, 0, 0, totalUnlocked().add(deltaUnlocked));
        }

        // check unstake amount
        require(
            amount <= totalStakedFor(addr),
            "SuperNova: preview amount exceeds balance"
        );

        // compute unstake amount in shares
        uint256 shares = totalStakingShares.mul(amount).div(totalStaked());
        require(shares > 0, "SuperNova: preview amount too small");

        uint256 rawShareSeconds = 0;
        uint256 timeBonusShareSeconds = 0;

        // compute first-in-last-out, time bonus weighted, share seconds
        uint256 i = userStakes[addr].length.sub(1);
        while (shares > 0) {
            Stake storage s = userStakes[addr][i];
            uint256 time = block.timestamp.sub(s.timestamp);

            if (s.shares < shares) {
                rawShareSeconds = rawShareSeconds.add(s.shares.mul(time));
                timeBonusShareSeconds = timeBonusShareSeconds.add(
                    s.shares.mul(time).mul(timeBonus(time)).div(
                        10**BONUS_DECIMALS
                    )
                );
                shares = shares.sub(s.shares);
            } else {
                rawShareSeconds = rawShareSeconds.add(shares.mul(time));
                timeBonusShareSeconds = timeBonusShareSeconds.add(
                    shares.mul(time).mul(timeBonus(time)).div(
                        10**BONUS_DECIMALS
                    )
                );
                break;
            }
            // this will throw on underflow
            i = i.sub(1);
        }

        // apply polar bonus
        uint256 polarBonusShareSeconds = polarBonus(polar)
            .mul(timeBonusShareSeconds)
            .div(10**BONUS_DECIMALS);

        // compute rewards based on expected updates
        uint256 expectedTotalShareSeconds = totalStakingShareSeconds
            .add((block.timestamp.sub(lastUpdated)).mul(totalStakingShares))
            .add(polarBonusShareSeconds)
            .sub(rawShareSeconds);

        uint256 reward = (totalUnlocked().add(deltaUnlocked))
            .mul(polarBonusShareSeconds)
            .div(expectedTotalShareSeconds);

        // compute effective bonus
        uint256 bonus = uint256(10**BONUS_DECIMALS)
            .mul(polarBonusShareSeconds)
            .div(rawShareSeconds);

        return (
            reward,
            bonus,
            rawShareSeconds,
            totalUnlocked().add(deltaUnlocked)
        );
    }

    function unlockFundInSec(uint256 timestamp) external view returns (uint256 unlockAmount) {
        unlockAmount = 0;
        uint256 fundingLen = fundings.length;
        for (uint8 i=0; i<fundingLen; i++) {
            Funding storage funding = fundings[i];
            if (timestamp < funding.end) {
                unlockAmount = unlockAmount.add((funding.shares).div(funding.duration));
            }
        }
    }
}
