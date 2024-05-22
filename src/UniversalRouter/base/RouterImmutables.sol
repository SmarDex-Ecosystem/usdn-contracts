// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/**
 * @dev Structure to hold the immutable parameters for the router
 * @param permit2 The permit2 address
 * @param weth9 The WETH9 address
 * @param v2Factory The v2 factory address
 * @param v3Factory The v3 factory address
 * @param pairInitCodeHash The v2 pair hash
 * @param poolInitCodeHash The v3 pool hash
 */
struct RouterParameters {
    address permit2;
    address weth9;
    address v2Factory;
    address v3Factory;
    bytes32 pairInitCodeHash;
    bytes32 poolInitCodeHash;
}
