// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

struct LidoParameters {
    address steth;
    address wsteth;
}

contract LidoImmutables {
    /// @dev The address of steth
    address public immutable STETH;

    /// @dev The address of wrapped steth
    address public immutable WSTETH;

    constructor(LidoParameters memory params) {
        STETH = params.steth;
        WSTETH = params.wsteth;
    }
}
