// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract LidoImmutables {
    /// @dev The address of steth
    IERC20Metadata public immutable STETH;

    /// @dev The address of wrapped steth
    IWstETH internal immutable WSTETH;

    /// @param wsteth Address of wrapped steth
    constructor(address wsteth) {
        WSTETH = IWstETH(wsteth);
        STETH = IERC20Metadata(WSTETH.stETH());
    }
}
