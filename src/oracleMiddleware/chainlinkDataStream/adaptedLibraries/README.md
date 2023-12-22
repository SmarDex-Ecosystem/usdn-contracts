# Adapted Chainlink libraries

This directory contains the adapted Chainlink libraries that are used in the Chainlink Data Stream.
Some of the libraries use incompatible Solidity versions, so they need to be adapted to be used in USDN project.  

USDN project uses Solidity version 0.8.20, and some of the libraries use strict older versions.
e.g. `pragma solidity 0.8.16;`.

## Adapted libraries

 - `@chainlink/contracts/src/v0.8/libraries/Common.sol` - adapted to use `pragma solidity 0.8.20;`
 - `@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IRewardManager.sol` - adapted to use `pragma solidity 0.8.20;`
 - `@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol` - adapted to use `pragma solidity 0.8.20;`