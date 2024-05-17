// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

struct UsdnParameters {
    address usdn;
    address wusdn;
    address usdnProtocol;
}

contract UsdnImmutables {
    /// @dev The address of usdn
    address internal immutable USDN;

    /// @dev The address of wrapped usdn
    address internal immutable WUSDN;

    /// @dev The address of usdn protocol
    address internal immutable USDN_PROTOCOL;

    constructor(UsdnParameters memory params) {
        USDN = params.usdn;
        WUSDN = params.wusdn;
        USDN_PROTOCOL = params.usdnProtocol;
    }
}
