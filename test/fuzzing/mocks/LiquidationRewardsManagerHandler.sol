// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IWstETH } from "../../../../src/interfaces/IWstETH.sol";
import { LiquidationRewardsManager } from "../../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";

/**
 * @title LiquidationRewardsManagerHandler
 * @dev Wrapper to aid in testing the LiquidationRewardsManager
 */
contract LiquidationRewardsManagerHandler is LiquidationRewardsManager, Test {
    constructor(IWstETH wstETH) LiquidationRewardsManager(wstETH) { }
}
