// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PriceController, IWstETH } from "src/oracleMiddleware/controller/PriceController.sol";

contract MockPriceController is PriceController {
    constructor(IWstETH wsteth) PriceController(wsteth) { }
}
