// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

struct SmardexParameters {
    address sdex;
    address usdn;
    address wusdn;
    address usdnProtocol;
}

contract SmardexImmutables {
    /// @dev The address of sdex
    address internal immutable SDEX;

    /// @dev The address of usdn
    address internal immutable USDN;

    /// @dev The address of wrapped usdn
    address internal immutable WUSDN;

    /// @dev The address of usdn protocol
    address internal immutable USDN_PROTOCOL;

    constructor(SmardexParameters memory params) {
        SDEX = params.sdex;
        USDN = params.usdn;
        WUSDN = params.wusdn;
        USDN_PROTOCOL = params.usdnProtocol;
    }
}
