// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { OrderManager } from "src/OrderManager.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title OrderManagerHandler
 */
contract OrderManagerHandler is OrderManager {
    constructor(IUsdnProtocol protocol) OrderManager(protocol) { }
}
