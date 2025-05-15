// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeploymentConfig } from "./DeploymentConfig.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

import { ILiquidationRewardsManager } from
    "../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IOracleMiddlewareWithPyth } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareWithPyth.sol";
import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocolFallback } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { Sdex } from "../../test/utils/Sdex.sol";

/// @notice Configuration contract for the USDN protocol backed with WUSDN deployment.
contract UsdnWusdnEthConfig is DeploymentConfig {
    address constant CHAINLINK_ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant PYTH_ADDRESS = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 constant PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    /// @dev As the ratio is already high by default, the max value needs to be even higher.
    uint256 constant MAX_SDEX_BURN_RATIO = type(uint32).max; // ~4294%
    uint256 constant MAX_MIN_LONG_POSITION = 10_000 ether;

    constructor() {
        // TODO decide of an initial amount
        INITIAL_LONG_AMOUNT = 250_000 ether;
        SDEX = Sdex(0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF);
        UNDERLYING_ASSET = IWusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

        initStorage.minLeverage = 10 ** Constants.LEVERAGE_DECIMALS + 10 ** (Constants.LEVERAGE_DECIMALS - 1); // x1.1
        initStorage.maxLeverage = 25 * 10 ** Constants.LEVERAGE_DECIMALS; // x10
        initStorage.lowLatencyValidatorDeadline = 15 minutes;
        initStorage.onChainValidatorDeadline = 65 minutes; // slightly more than chainlink's heartbeat
        initStorage.safetyMarginBps = 200; // 2%
        initStorage.liquidationIteration = 1;
        initStorage.protocolFeeBps = 800; // 8%
        initStorage.rebalancerBonusBps = 8750; // 87.5%
        initStorage.liquidationPenalty = 200; // 200 ticks -> ~2.02%
        initStorage.emaPeriod = 16 hours;
        initStorage.fundingSF = 75 * 10 ** (Constants.FUNDING_SF_DECIMALS - 2); // 0.75
        initStorage.feeThreshold = 2000 ether;
        initStorage.openExpoImbalanceLimitBps = 400; // 4%
        initStorage.withdrawalExpoImbalanceLimitBps = 600; // 6%
        initStorage.depositExpoImbalanceLimitBps = 400; // 4%
        initStorage.closeExpoImbalanceLimitBps = 600; // 6%
        initStorage.rebalancerCloseExpoImbalanceLimitBps = 250; // 2.5%
        initStorage.longImbalanceTargetBps = 300; // 3%
        initStorage.positionFeeBps = 1; // 0.01%
        initStorage.vaultFeeBps = 4; // 0.04%
        initStorage.sdexRewardsRatioBps = 100; // 1%
        // for each syntETH, 75 SDEX will be burned
        initStorage.sdexBurnOnDepositRatio = uint64(75 * Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR); // x75
        initStorage.securityDepositValue = 0.15 ether;
        initStorage.EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4)); // 0.0003
        initStorage.tickSpacing = 100;
        initStorage.sdex = SDEX;
        initStorage.asset = UNDERLYING_ASSET;
        // 1400 wusdn (to roughly match the current minLongPosition of the wstETH/USD version)
        initStorage.minLongPosition = 1400 * 10 ** UNDERLYING_ASSET.decimals();
    }

    /// @inheritdoc DeploymentConfig
    function _setPeripheralContracts(
        IOracleMiddlewareWithPyth oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        IUsdn usdnNoRebase
    ) internal override {
        initStorage.oracleMiddleware = oracleMiddleware;
        initStorage.liquidationRewardsManager = liquidationRewardsManager;
        uint8 priceFeedDecimals = oracleMiddleware.getDecimals();
        // set usdn prices for compatibility as the usdn token used does not rebase
        initStorage.targetUsdnPrice = uint128(10 ** priceFeedDecimals);
        initStorage.usdnRebaseThreshold = uint128(10 ** priceFeedDecimals);
        initStorage.usdn = usdnNoRebase;
    }

    /// @inheritdoc DeploymentConfig
    function _setFeeCollector(address feeCollector) internal override {
        initStorage.feeCollector = feeCollector;
    }

    /// @inheritdoc DeploymentConfig
    function _setProtocolFallback(IUsdnProtocolFallback protocolFallback) internal override {
        initStorage.protocolFallbackAddr = address(protocolFallback);
    }
}
