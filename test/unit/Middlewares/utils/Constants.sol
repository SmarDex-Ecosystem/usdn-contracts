// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/* -------------------------------------------------------------------------- */
/*                             Mocked oracle data                             */
/* -------------------------------------------------------------------------- */

uint256 constant ETH_PRICE = 2000e8;
uint256 constant ETH_CONF = 20e8;
uint256 constant ETH_DECIMALS = 8;

bytes constant MOCK_PYTH_DATA = hex"504e41550000000000000000000000000000000000000000000000000000000011";

uint256 constant REDSTONE_ETH_PRICE = 3838.09610965 ether;
uint48 constant REDSTONE_ETH_TIMESTAMP = 1_717_684_100;
// the data must be padded to a multiple of 32 bytes by adding zeroes to the beginning
// since redstone parses from the end of the calldata
bytes constant REDSTONE_ETH_DATA =
    hex"00000000000000004554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000595cd5e4d5018fedf35ba00000002000000196c710f6ee933d08f86e99def2c6c64684808705691289aef63503f54bf8b9202d21cde463aeef0830cea7795a03cbebd92d51a7eb13134129fc82e3cac26e2e1b4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000595cd4a962018fedf35ba0000000200000015bd816c1b59f67af5990b834c572b1e403a6a7ffcbc78e13510a0b7de750e02a4d0c641de3797cc2225fd6064f7445d0d77808ec620bd96f84e298bea049ac2f1c4554480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000595cd5e4d5018fedf35ba000000020000001ab05ff923cef4ea56a1b77af4ea5f2700cab64628b44aaf460b7d9950dff4c1e74da926233820b52b78644fce28a97dc7b88c25bbe1dbd173ff69e8e3c1dcef01b0003000000000002ed57011e0000";

uint256 constant STREAM_ETH_PRICE = 2000 ether;
