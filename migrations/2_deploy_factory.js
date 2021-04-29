// deploy SUPERNOVA factory

const SuperNovaFactory = artifacts.require('SuperNovaFactory');

// set address of POLAR token contract
const POLAR_ADDRESS = '0x70905594023Cb2f37F3103fDc70315ad1601D6EF';
const FEE_COLLECTOR = '0x90588b57B543fa08FFC210D4F5cEF09E920C99de';

module.exports = function (deployer) {
    deployer.deploy(SuperNovaFactory, POLAR_ADDRESS, FEE_COLLECTOR);
}
