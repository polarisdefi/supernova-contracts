# SuperNova core

This repository contains the Solidity contracts for SuperNova core, Supernova factory, and POLAR token.




## Setup

Both **Node.js** and **npm** are required for package management and testing. See instructions
for installation [here](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm). This
codebase has been tested with `Node.js: v10.16.0` and `npm: 6.9.0`.

This project uses [OpenZeppelin](https://docs.openzeppelin.com/cli/2.8/) libraries and tools.
To install these packages along with other dependencies:
```
npm install
```


## Test

To run all unit tests
```
npm test
```

To run some subset of tests
```
npx mocha --exit --grep withdraw
```


## Deploy

To deploy POLAR token to Ropsten
```
npx truffle migrate --network ropsten --f 1 --to 1
```

Once POLAR token is deployed, set the `GYSR_ADDRESS` constant at the top of `migrations/2_deploy_factory.js`.


To deploy the SuperNova factory contract to Ropsten
```
npx truffle migrate --network ropsten --f 2 --to 2
```


To Verify the contracts deployed from Truffle 
```
truffle run verify SuperNovaFactory --network binance_test
```

For SuperNova, Use Test.sol file and https://abi.hashex.org/ to get constructor abi encoded

Opitimzation Yes and : 10000 
Liscence : MIT