// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ISmardexFactory } from "src/UniversalRouter/interfaces/ISmardexFactory.sol";

struct SmardexParameters {
    ISmardexFactory smardexFactory;
    address weth;
}

contract SmardexImmutables {
    /// @dev The SmardexFactory
    ISmardexFactory internal immutable SMARDEX_FACTORY;

    /// @dev The address of weth
    address internal immutable WETH;

    constructor(SmardexParameters memory params) {
        SMARDEX_FACTORY = params.smardexFactory;
        WETH = params.weth;
    }
}
