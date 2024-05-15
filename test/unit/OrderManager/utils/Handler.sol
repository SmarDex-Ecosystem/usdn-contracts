// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { OrderManager } from "src/OrderManager/OrderManager.sol";

/**
 * @title OrderManagerHandler
 * @dev Wrapper to aid in testing the order manager
 */
contract OrderManagerHandler is OrderManager, Test {
    constructor(IUsdnProtocol usdnProtocol) OrderManager(usdnProtocol) { }

    /// @dev Sets the position version to the current one + 1
    function incrementPositionVersion() external {
        ++_positionVersion;
    }
}
