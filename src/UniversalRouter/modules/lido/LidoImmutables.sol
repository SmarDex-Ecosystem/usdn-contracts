// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { IStETH } from "src/UniversalRouter/interfaces/IStETH.sol";

/**
 * @notice Parameters for the Lido module
 * @param wsteth Address of wrapped steth
 */
struct LidoParameters {
    address wsteth;
}

contract LidoImmutables {
    /// @dev The address of steth
    IStETH public immutable STETH;

    /// @dev The address of wrapped steth
    IWstETH internal immutable WSTETH;

    /// @param params The immutable parameters of the Lido module
    constructor(LidoParameters memory params) {
        WSTETH = IWstETH(params.wsteth);
        STETH = IStETH(WSTETH.stETH());
    }
}
