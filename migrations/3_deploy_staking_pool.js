// deploy geyser factory

const Geyser = artifacts.require('Geyser');

// set address of GYSR token contract
const _GYSER = '0x1C545E9943CFd1b41E60a7917465911fa00Fc28C';
const STAKING_TOKEN = '0x6aab392d709e7e9a43009ff06fa2e5c33372b07d';
const REWARDED_TOKEN = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
const MIN_BONUS = 33;
const MAX_BONUS = 100
const DURATION = 432000;
module.exports = function (deployer) {
    // deployer.deploy(Geyser, STAKING_TOKEN, REWARDED_TOKEN, MIN_BONUS, MAX_BONUS, DURATION, _GYSER);
}
