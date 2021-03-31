// deploy SUPERNOVA factory

const SuperNovaFactory = artifacts.require('SuperNovaFactory');

// set address of POLAR token contract
const POLAR_ADDRESS = '0x3a5325F0E5Ee4da06a285E988f052D4e45Aa64b4';

module.exports = function (deployer) {
    deployer.deploy(SuperNovaFactory, POLAR_ADDRESS);
}
