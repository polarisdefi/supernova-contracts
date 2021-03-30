// deploy SUPERNOVA factory

const SuperNovaFactory = artifacts.require('SuperNovaFactory');

// set address of POLAR token contract
const POLAR_ADDRESS = '0x1C545E9943CFd1b41E60a7917465911fa00Fc28C';

module.exports = function (deployer) {
    deployer.deploy(SuperNovaFactory, POLAR_ADDRESS);
}
