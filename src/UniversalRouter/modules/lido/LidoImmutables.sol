// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { ILidoImmutables } from "src/interfaces/UniversalRouter/ILidoImmutables.sol";

contract LidoImmutables is ILidoImmutables {
    /// @inheritdoc ILidoImmutables
    IERC20Metadata public immutable STETH;

    /// @dev The address of the wrapped steth
    IWstETH internal immutable WSTETH;

    /// @param wsteth The address of wrapped steth
    constructor(address wsteth) {
        WSTETH = IWstETH(wsteth);
        STETH = IERC20Metadata(WSTETH.stETH());
    }
}
