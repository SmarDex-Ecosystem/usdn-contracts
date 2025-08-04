// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeploymentConfig } from "./DeploymentConfig.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { ILiquidationRewardsManager } from
    "../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IOracleMiddlewareWithPyth } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareWithPyth.sol";
import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolFallback } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { Sdex } from "../../test/utils/Sdex.sol";

/// @notice Configuration contract for the USDN protocol backed with WSTETH deployment.
contract UsdnCbbtcUsdConfig is DeploymentConfig {
    address constant CHAINLINK_CBBTC_PRICE = 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;
    address constant PYTH_ADDRESS = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;
    IERC20Metadata constant CBBTC = IERC20Metadata(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
    bytes32 constant PYTH_BTC_FEED_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    uint256 constant CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    uint256 constant MAX_SDEX_BURN_RATIO = Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 10; // 10%
    uint256 constant MAX_MIN_LONG_POSITION = 10 ether;

    constructor() {
        INITIAL_LONG_AMOUNT = 20 ether;
        SDEX = Sdex(0xFd4330b0312fdEEC6d4225075b82E00493FF2e3f);
        UNDERLYING_ASSET = CBBTC;

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
        initStorage.asset = UNDERLYING_ASSET;
        initStorage.minLongPosition = 2 * 10 ** UNDERLYING_ASSET.decimals(); // 2 tokens
    }

    /// @inheritdoc DeploymentConfig
    function _setPeripheralContracts(
        IOracleMiddlewareWithPyth oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        IUsdn usdn
    ) internal override {
        initStorage.oracleMiddleware = oracleMiddleware;
        uint8 priceFeedDecimals = oracleMiddleware.getDecimals();
        initStorage.liquidationRewardsManager = liquidationRewardsManager;
        initStorage.targetUsdnPrice = uint128(10_087 * 10 ** (priceFeedDecimals - 4)); // $1.0087
        initStorage.usdnRebaseThreshold = uint128(1009 * 10 ** (priceFeedDecimals - 3)); // $1.009
        initStorage.usdn = usdn;
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
