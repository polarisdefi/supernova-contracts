// deploy SUPERNOVA factory

const SuperNovaFactory = artifacts.require('SuperNovaFactory');

// set address of POLAR token contract
const POLAR_ADDRESS = '0x70905594023Cb2f37F3103fDc70315ad1601D6EF';

module.exports = function (deployer) {
    deployer.deploy(SuperNovaFactory, POLAR_ADDRESS);
}
