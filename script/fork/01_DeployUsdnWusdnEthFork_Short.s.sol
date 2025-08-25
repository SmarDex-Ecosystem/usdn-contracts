// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeployUsdnWusdnEth } from "../01_DeployUsdnWusdnEth.s.sol";

import { LiquidationRewardsManagerWusdn } from "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";
import { WusdnToEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WusdnToEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";

import { UsdnNoRebase } from "../../src/Usdn/UsdnNoRebase.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

import { UsdnForkBase } from "./UsdnForkBase.s.sol";

contract DeployUsdnWusdnFork is UsdnForkBase, DeployUsdnWusdnEth {
    constructor()
        UsdnForkBase(UNDERLYING_ASSET, PYTH_ADDRESS, CHAINLINK_ETH_PRICE, PYTH_ETH_FEED_ID, CHAINLINK_PRICE_VALIDITY)
        DeployUsdnWusdnEth()
    {
        UNDERLYING_ASSET = IWusdn(vm.envOr("UNDERLYING_ADDRESS_SHORTDN", address(WUSDN)));
        price = vm.envOr("START_PRICE_SHORTDN", price);
    }

    function run()
        public
        virtual
        override
        returns (
            WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware_,
            LiquidationRewardsManagerWusdn liquidationRewardsManagerWusdn_,
            Rebalancer rebalancer_,
            UsdnNoRebase usdnNoRebase_,
            IUsdnProtocol usdnProtocol_
        )
    {
        super.preRun();
        (wusdnToEthOracleMiddleware_, liquidationRewardsManagerWusdn_, rebalancer_, usdnNoRebase_, usdnProtocol_) =
            super.run();
        super.postRun(usdnProtocol_);
    }
}
