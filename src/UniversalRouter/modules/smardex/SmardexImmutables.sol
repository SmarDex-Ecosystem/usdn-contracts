// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

struct SmardexParameters {
    address smardexFactory;
    address weth;
}

contract SmardexImmutables {
    /// @dev The address of SmardexFactory
    address internal immutable SMARDEX_FACTORY;

    /// @dev The address of weth
    address internal immutable WETH;

    constructor(SmardexParameters memory params) {
        SMARDEX_FACTORY = params.smardexFactory;
        WETH = params.weth;
    }
}
