// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             Mocked oracle data                             */
/* -------------------------------------------------------------------------- */

uint256 constant ETH_PRICE = 2000e8;
uint256 constant ETH_CONF = 20e8;
uint256 constant ETH_DECIMALS = 8;

bytes constant MOCK_PYTH_DATA = hex"504e41550000000000000000000000000000000000000000000000000000000011";

uint256 constant REDSTONE_ETH_PRICE = 3840.83956166 ether;
uint48 constant REDSTONE_ETH_TIMESTAMP = 1_717_678_570;
// the data must be padded to a multiple of 32 bytes by adding zeroes to the beginning
// since redstone parses from the end of the calldata
bytes constant REDSTONE_ETH_DATA =
    hex"000000004554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000596d3011c6018fed9efa10000000200000013674ee3c7d363f96f72d46b53a07aa6e6d9976a4ace1c8491892a5007cbd17045d9b1c4654958a74d38d18034628508f9e3a762651894a4c8cc269611b190cd21c0001000000000002ed57011e0000";
