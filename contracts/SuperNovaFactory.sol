/*
Supernova Factory 
This implements the core Supernova contract, which allows for generalized staking, yield farming, and token distribution. This also implements the POLAR spending mechanic for boosted reward distribution.

Credit to: 
https://github.com/ampleforth/token-geyser
https://github.com/gysr-io/core
SPDX-License-Identifier: MIT
*/

pragma solidity ^0.6.12;

import "./ISuperNovaFactory.sol";
import "./SuperNova.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SuperNovaFactory is ISuperNovaFactory,Ownable {
    // fields
    mapping(address => bool) public map;
    address[] public list;
    address private _supernova;

    address public _feeCollector;
    /**
     * @param supernova_ address of SuperNova token
     */
    constructor(address supernova_, address feeCollector_) public {
        _supernova = supernova_;
        _feeCollector = feeCollector_;
    }

    function setFeeCollector(address feeCollector_) public onlyOwner {
        require(feeCollector_ != address(0), "SUPERNOVA FACTORY : address cannot be null");
        _feeCollector = feeCollector_;
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
        SuperNova superNova = new SuperNova(
            stakingToken,
            rewardToken,
            bonusMin,
            bonusMax,
            bonusPeriod,
            _supernova,
            _feeCollector
        );
        superNova.transferOwnership(msg.sender);

        // bookkeeping
        map[address(superNova)] = true;
        list.push(address(superNova));

        // output
        emit SuperNovaCreated(msg.sender, address(superNova));
        return address(superNova);
    }

    /**
     * @return total number of Geysers created by the factory
     */
    function count() public view returns (uint256) {
        return list.length;
    }
}
