// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { LiquidationRewardsManager } from "../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DefaultConfig {
    uint256 constant MAX_SDEX_BURN_RATIO = Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 10; // 10%
    uint256 constant MAX_MIN_LONG_POSITION = 10 ether;

    Types.InitStorage internal initStorage;

    constructor() {
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
    }

    function _setPeripheralContracts(
        WstEthOracleMiddleware oracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager,
        Usdn usdn,
        IWstETH wstETH,
        address usdnProtocolFallback,
        address feeCollector,
        IERC20Metadata sdex
    ) internal {
        initStorage.oracleMiddleware = oracleMiddleware;
        uint8 priceFeedDecimals = oracleMiddleware.getDecimals();
        initStorage.liquidationRewardsManager = liquidationRewardsManager;
        initStorage.targetUsdnPrice = uint128(10_087 * 10 ** (priceFeedDecimals - 4)); // $1.0087
        initStorage.usdnRebaseThreshold = uint128(1009 * 10 ** (priceFeedDecimals - 3)); // $1.009
        initStorage.usdn = usdn;
        initStorage.asset = wstETH;
        initStorage.minLongPosition = 2 * 10 ** wstETH.decimals(); // 2 tokens
        initStorage.protocolFallbackAddr = usdnProtocolFallback;
        initStorage.feeCollector = feeCollector;
        initStorage.sdex = sdex;
    }
}
