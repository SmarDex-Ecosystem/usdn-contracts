// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";

contract UsdnImmutables {
    /// @dev The address of the USDN
    IUsdn internal immutable USDN;

    constructor(IUsdn usdn) {
        USDN = usdn;
    }
}
