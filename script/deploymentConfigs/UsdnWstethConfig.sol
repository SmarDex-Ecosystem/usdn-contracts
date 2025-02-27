// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { LiquidationRewardsManager } from "../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { Sdex } from "../../test/utils/Sdex.sol";
import { DeploymentConfig } from "./DeploymentConfig.sol";

contract UsdnWstethConfig is DeploymentConfig {
    constructor() {
        CHAINLINK_ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;
        CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
        INITIAL_LONG_AMOUNT = 200 ether;
        PYTH_ADDRESS = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
        PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        SDEX = Sdex(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);
        WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

        initStorage.minLeverage = 10 ** Constants.LEVERAGE_DECIMALS + 10 ** (Constants.LEVERAGE_DECIMALS - 1); // x1.1
        initStorage.maxLeverage = 10 * 10 ** Constants.LEVERAGE_DECIMALS; // x10
        initStorage.lowLatencyValidatorDeadline = 15 minutes;
        initStorage.onChainValidatorDeadline = 65 minutes; // slightly more than chainlink's heartbeat
        initStorage.safetyMarginBps = 200; // 2%
        initStorage.liquidationIteration = 1;
        initStorage.protocolFeeBps = 800; // 8%
        initStorage.rebalancerBonusBps = 8000; // 80%
        initStorage.liquidationPenalty = 200; // 200 ticks -> ~2.02%
        initStorage.emaPeriod = 5 days;
        initStorage.fundingSF = 12 * 10 ** (Constants.FUNDING_SF_DECIMALS - 2); // 0.12
        initStorage.feeThreshold = 1 ether;
        initStorage.openExpoImbalanceLimitBps = 500; // 5%
        initStorage.withdrawalExpoImbalanceLimitBps = 600; // 6%
        initStorage.depositExpoImbalanceLimitBps = 500; // 5%
        initStorage.closeExpoImbalanceLimitBps = 600; // 6%
        initStorage.rebalancerCloseExpoImbalanceLimitBps = 350; // 3.5%
        initStorage.longImbalanceTargetBps = 400; // 4%
        initStorage.positionFeeBps = 4; // 0.04%
        initStorage.vaultFeeBps = 4; // 0.04%
        initStorage.sdexRewardsRatioBps = 100; // 1%
        initStorage.sdexBurnOnDepositRatio = 5e6; // 5%
        initStorage.securityDepositValue = 0.5 ether;
        initStorage.EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4)); // 0.0003
        initStorage.tickSpacing = 100;
        initStorage.sdex = SDEX;
        initStorage.asset = WSTETH;
        uint8 assetDecimals = WSTETH.decimals();
        initStorage.assetDecimals = assetDecimals;
        initStorage.minLongPosition = 2 * 10 ** assetDecimals; // 2 tokens
    }

    function _setPeriferalContracts(
        WstEthOracleMiddleware oracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager,
        Usdn usdn
    ) internal {
        initStorage.oracleMiddleware = oracleMiddleware;
        uint8 priceFeedDecimals = oracleMiddleware.getDecimals();
        initStorage.priceFeedDecimals = priceFeedDecimals;
        initStorage.liquidationRewardsManager = liquidationRewardsManager;
        initStorage.targetUsdnPrice = uint128(10_087 * 10 ** (priceFeedDecimals - 4)); // $1.0087
        initStorage.usdnRebaseThreshold = uint128(1009 * 10 ** (priceFeedDecimals - 3)); // $1.009
        initStorage.usdn = usdn;
    }

    function _setFeeCollector(address feeCollector) internal {
        initStorage.feeCollector = feeCollector;
    }
}
