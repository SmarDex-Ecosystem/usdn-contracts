// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { ISmardexFactory } from "src/interfaces/UniversalRouter/smardex/ISmardexFactory.sol";
import { IWETH9 } from "@uniswap/universal-router/contracts/interfaces/external/IWETH9.sol";

/**
 * @notice The smardex parameter struct
 * @param smardexFactory The smardex factory
 * @param weth The wrapped ETH address
 */
struct SmardexParameters {
    ISmardexFactory smardexFactory;
    address weth;
}

contract SmardexImmutables {
    /// @dev The smardex factory
    ISmardexFactory internal immutable SMARDEX_FACTORY;

    /// @dev The wrapped ETH
    IWETH9 internal immutable WETH;

    constructor(SmardexParameters memory params) {
        SMARDEX_FACTORY = params.smardexFactory;
        WETH = IWETH9(params.weth);
    }
}
