// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeployUsdnWusdnEth } from "../01_DeployUsdnWusdnEth.s.sol";

import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";

import { UsdnForkBase } from "./UsdnForkBase.s.sol";

contract DeployUsdnWusdnFork is UsdnForkBase, DeployUsdnWusdnEth {
    constructor()
        UsdnForkBase(UNDERLYING_ASSET, PYTH_ADDRESS, CHAINLINK_ETH_PRICE, PYTH_ETH_FEED_ID, CHAINLINK_PRICE_VALIDITY)
        DeployUsdnWusdnEth()
    {
        UNDERLYING_ASSET = IWusdn(vm.envOr("UNDERLYING_ADDRESS_USDN", address(WUSDN)));
        price = vm.envOr("START_PRICE_SHORTDN", price);
    }
}
