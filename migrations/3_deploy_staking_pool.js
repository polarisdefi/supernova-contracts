// deploy geyser factory

const SuperNova = artifacts.require('SuperNova');

// set address of GYSR token contract
const _GYSER = '0x70905594023cb2f37f3103fdc70315ad1601d6ef';
const STAKING_TOKEN = '0x70905594023cb2f37f3103fdc70315ad1601d6ef';
const REWARDED_TOKEN = '0x70905594023cb2f37f3103fdc70315ad1601d6ef';
const MIN_BONUS = 1;
const MAX_BONUS = 2
const DURATION = 7776000;
module.exports = function (deployer) {
    // deployer.deploy(SuperNova, STAKING_TOKEN, REWARDED_TOKEN, MIN_BONUS, MAX_BONUS, DURATION, _GYSER);
}
