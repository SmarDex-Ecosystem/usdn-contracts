// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { LiquidationRewardsManagerWstEth } from
    "../../../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";

/**
 * @title LiquidationRewardsManagerHandler
 * @dev Wrapper to aid in testing the LiquidationRewardsManager
 */
contract LiquidationRewardsManagerHandler is LiquidationRewardsManagerWstEth, Test {
    constructor(IWstETH wstETH) LiquidationRewardsManagerWstEth(wstETH) { }
}
