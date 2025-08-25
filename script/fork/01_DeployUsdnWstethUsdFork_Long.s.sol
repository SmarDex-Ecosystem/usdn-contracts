// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeployUsdnWstethUsd } from "../01_DeployUsdnWstethUsd.s.sol";

import { LiquidationRewardsManagerWstEth } from
    "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
import { WstEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../src/Usdn/Wusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

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

    function run()
        public
        virtual
        override
        returns (
            WstEthOracleMiddlewareWithPyth wstEthOracleMiddleware_,
            LiquidationRewardsManagerWstEth liquidationRewardsManager_,
            Rebalancer rebalancer_,
            Usdn usdn_,
            Wusdn wusdn_,
            IUsdnProtocol usdnProtocol_
        )
    {
        super.preRun();
        (wstEthOracleMiddleware_, liquidationRewardsManager_, rebalancer_, usdn_, wusdn_, usdnProtocol_) = super.run();
        super.postRun(usdnProtocol_);
    }
}
