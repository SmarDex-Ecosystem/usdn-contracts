// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";
import { WstETH } from "../../../utils/WstEth.sol";

import { LiquidationRewardsManagerWsteth } from
    "../../../../src/LiquidationRewardsManager/LiquidationRewardsManagerWsteth.sol";

/**
 * @title LiquidationRewardsManagerBaseFixture
 * @dev Utils for testing the liquidation rewards manager
 */
contract LiquidationRewardsManagerBaseFixture is BaseFixture {
    WstETH internal wsteth;
    LiquidationRewardsManagerWsteth internal liquidationRewardsManager;

    function setUp() public virtual {
        vm.warp(1_704_063_600); // 01/01/2024 @ 12:00am (UTC+2)

        wsteth = new WstETH();
        liquidationRewardsManager = new LiquidationRewardsManagerWsteth(wsteth);
    }
}
