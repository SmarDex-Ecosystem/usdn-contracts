// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IWETH9 } from "../interfaces/external/IWETH9.sol";
import { IAllowanceTransfer } from "src/UniversalRouter/interfaces/IAllowanceTransfer.sol";

struct PaymentsParameters {
    address permit2;
    address weth9;
}

contract PaymentsImmutables {
    /// @dev WETH9 address
    IWETH9 internal immutable WETH9;

    /// @dev Permit2 address
    IAllowanceTransfer internal immutable PERMIT2;

    constructor(PaymentsParameters memory params) {
        WETH9 = IWETH9(params.weth9);
        PERMIT2 = IAllowanceTransfer(params.permit2);
    }
}
