// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeployUsdnWusdnEth } from "../01_DeployUsdnWusdnEth.s.sol";
import { ForkCore } from "./ForkCore.s.sol";

import { LiquidationRewardsManagerWusdn } from "../../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";
import { WusdnToEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WusdnToEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { UsdnNoRebase } from "../../src/Usdn/UsdnNoRebase.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract DeployShortdnFork is ForkCore, DeployUsdnWusdnEth {
    constructor()
        ForkCore(address(WUSDN), PYTH_ADDRESS, CHAINLINK_ETH_PRICE, PYTH_ETH_FEED_ID, CHAINLINK_PRICE_VALIDITY)
        DeployUsdnWusdnEth()
    {
        UNDERLYING_ASSET = IWusdn(vm.envOr("UNDERLYING_ADDRESS_WUSDN", address(WUSDN)));
        WUSDN = IWusdn(address(UNDERLYING_ASSET));
        price = vm.envOr("START_PRICE_SHORTDN", price);
        initStorage.asset = UNDERLYING_ASSET;
        initStorage.sdexBurnOnDepositRatio = uint64(MAX_SDEX_BURN_RATIO);
    }

    function run()
        public
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
