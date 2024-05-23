// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/**
 * @notice Parameters for the Lido module
 * @param steth Address of steth
 * @param wsteth Address of wrapped steth
 */
struct LidoParameters {
    address steth;
    address wsteth;
}

contract LidoImmutables {
    /// @dev The address of steth
    address public immutable STETH;

    /// @dev The address of wrapped steth
    address public immutable WSTETH;

    /// @param params The immutable parameters of the Lido module
    constructor(LidoParameters memory params) {
        STETH = params.steth;
        WSTETH = params.wsteth;
    }
}
