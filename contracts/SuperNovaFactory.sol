/*
Supernova Factory 
This implements the core Supernova contract, which allows for generalized staking, yield farming, and token distribution. This also implements the POLAR spending mechanic for boosted reward distribution.
8:05
Credit to: 
https://github.com/ampleforth/token-geyser
https://github.com/gysr-io/core
SPDX-License-Identifier: MIT
*/

pragma solidity ^0.6.12;

import "./ISuperNovaFactory.sol";
import "./Geyser.sol";

contract SuperNovaFactory is ISuperNovaFactory {
    // fields
    mapping(address => bool) public map;
    address[] public list;
    address private _supernova;

    /**
     * @param supernova_ address of SuperNova token
     */
    constructor(address supernova_) public {
        _supernova = supernova_;
    }

    /**
     * @inheritdoc ISuperNovaFactory
     */
    function create(
        address stakingToken,
        address rewardToken,
        uint256 bonusMin,
        uint256 bonusMax,
        uint256 bonusPeriod
    ) public override returns (address) {
        // create
        Geyser geyser = new Geyser(
            stakingToken,
            rewardToken,
            bonusMin,
            bonusMax,
            bonusPeriod,
            _supernova
        );
        geyser.transferOwnership(msg.sender);

        // bookkeeping
        map[address(geyser)] = true;
        list.push(address(geyser));

        // output
        emit SuperNovaCreated(msg.sender, address(geyser));
        return address(geyser);
    }

    /**
     * @return total number of Geysers created by the factory
     */
    function count() public view returns (uint256) {
        return list.length;
    }
}
