/*
Supernova interface

This defines the core SuperNova contract interface as an extension to the
standard IStaking interface

SPDX-License-Identifier: MIT
*/

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStaking.sol";

/**
 * @title SuperNova interface
 */
abstract contract ISuperNova is IStaking, Ownable {
    // events
    event RewardsDistributed(address indexed user, uint256 amount);
    event RewardsFunded(
        uint256 amount,
        uint256 duration,
        uint256 start,
        uint256 total
    );
    event RewardsUnlocked(uint256 amount, uint256 total);
    event RewardsExpired(uint256 amount, uint256 duration, uint256 start);
    event PolarSpent(address indexed user, uint256 amount);
    event PolarWithdrawn(uint256 amount);

    // IStaking
    /**
     * @notice no support for history
     * @return false
     */
    function supportsHistory() external override pure returns (bool) {
        return false;
    }

    // ISuperNova
    /**
     * @return staking token for this SuperNova
     */
    function stakingToken() external virtual view returns (address);

    /**
     * @return reward token for this SuperNova
     */
    function rewardToken() external virtual view returns (address);

    /**
     * @notice fund SuperNova by locking up reward tokens for distribution
     * @param amount number of reward tokens to lock up as funding
     * @param duration period (seconds) over which funding will be unlocked
     */
    function fund(uint256 amount, uint256 duration) external virtual;

    /**
     * @notice fund SuperNova by locking up reward tokens for future distribution
     * @param amount number of reward tokens to lock up as funding
     * @param duration period (seconds) over which funding will be unlocked
     * @param start time (seconds) at which funding begins to unlock
     */
    function fund(
        uint256 amount,
        uint256 duration,
        uint256 start
    ) external virtual;

    /**
     * @notice withdraw POLAR tokens applied during unstaking
     * @param amount number of POLAR to withdraw
     */
    function withdraw(uint256 amount) external virtual;

    /**
     * @notice unstake while applying POLAR token for boosted rewards
     * @param amount number of tokens to unstake
     * @param polar number of POLAR tokens to apply for boost
     */
    function unstake(
        uint256 amount,
        uint256 polar,
        bytes calldata
    ) external virtual;

    /**
     * @notice update accounting, unlock tokens, etc.
     */
    function update() external virtual;

    /**
     * @notice clean SuperNova, expire old fundings, etc.
     */
    function clean() external virtual;
}
