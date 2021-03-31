// deploy SUPERNOVA factory

const SuperNovaFactory = artifacts.require('SuperNovaFactory');

// set address of POLAR token contract
const POLAR_ADDRESS = '0x3a5325f0e5ee4da06a285e988f052d4e45aa64b4';

module.exports = function (deployer) {
    deployer.deploy(SuperNovaFactory, POLAR_ADDRESS);
}
