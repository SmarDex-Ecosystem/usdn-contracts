// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeployUsdnWstethUsd } from "../01_DeployUsdnWstethUsd.s.sol";

import { IWstETH } from "../../src/interfaces/IWstETH.sol";

import { UsdnForkBase } from "./UsdnForkBase.s.sol";

contract DeployUsdnWstethFork is UsdnForkBase, DeployUsdnWstethUsd {
    constructor()
        UsdnForkBase(UNDERLYING_ASSET, PYTH_ADDRESS, CHAINLINK_ETH_PRICE, PYTH_ETH_FEED_ID, CHAINLINK_PRICE_VALIDITY)
        DeployUsdnWstethUsd()
    {
        UNDERLYING_ASSET = IWstETH(vm.envOr("UNDERLYING_ADDRESS_WUSDN", address(WSTETH)));
        price = vm.envOr("START_PRICE_USDN", price);
    }
}
