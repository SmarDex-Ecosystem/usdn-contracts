// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { console, Test } from "forge-std/Test.sol";

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocol, Test {
    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        UsdnProtocol(usdn, asset, oracleMiddleware, tickSpacing)
    { }

    function getUserPendingAction(address user) external returns (PendingAction memory) {
        return _getPendingAction(user, false); // do not clear
    }
}
