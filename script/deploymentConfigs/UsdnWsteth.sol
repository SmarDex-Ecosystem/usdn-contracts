// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { LiquidationRewardsManager } from "../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { Sdex } from "../../test/utils/Sdex.sol";
import { DeployProtocolProd } from "../utils/DeployProtocolProd.sol";

contract UsdnWstethConfig is DeployProtocolProd {
    address constant CHAINLINK_ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant PYTH_ADDRESS = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 constant PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    IWstETH constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    uint256 constant CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    uint256 constant INITIAL_LONG_AMOUNT = 200 ether;

    constructor() {
        _storage._minLeverage = 10 ** Constants.LEVERAGE_DECIMALS + 10 ** (Constants.LEVERAGE_DECIMALS - 1); // x1.1
        _storage._maxLeverage = 10 * 10 ** Constants.LEVERAGE_DECIMALS; // x10
        _storage._lowLatencyValidatorDeadline = 15 minutes;
        _storage._onChainValidatorDeadline = 65 minutes; // slightly more than chainlink's heartbeat
        _storage._safetyMarginBps = 200; // 2%
        _storage._liquidationIteration = 1;
        _storage._protocolFeeBps = 800; // 8%
        _storage._rebalancerBonusBps = 8000; // 80%
        _storage._liquidationPenalty = 200; // 200 ticks -> ~2.02%
        _storage._EMAPeriod = 5 days;
        _storage._fundingSF = 12 * 10 ** (Constants.FUNDING_SF_DECIMALS - 2); // 0.12
        _storage._feeThreshold = 1 ether;
        _storage._openExpoImbalanceLimitBps = 500; // 5%
        _storage._withdrawalExpoImbalanceLimitBps = 600; // 6%
        _storage._depositExpoImbalanceLimitBps = 500; // 5%
        _storage._closeExpoImbalanceLimitBps = 600; // 6%
        _storage._rebalancerCloseExpoImbalanceLimitBps = 350; // 3.5%
        _storage._longImbalanceTargetBps = 400; // 4%
        _storage._positionFeeBps = 4; // 0.04%
        _storage._vaultFeeBps = 4; // 0.04%
        _storage._sdexRewardsRatioBps = 100; // 1%
        _storage._sdexBurnOnDepositRatio = 5e6; // 5%
        _storage._securityDepositValue = 0.5 ether;
        _storage._EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4));
        _storage._tickSpacing = 100;

        _storage._sdex = SDEX;
        _storage._asset = WSTETH;
        uint8 assetDecimals = WSTETH.decimals();
        _storage._assetDecimals = assetDecimals;
        _storage._minLongPosition = 2 * 10 ** assetDecimals; // 2 tokens
    }

    function _setPeriferalContracts(
        WstEthOracleMiddleware oracleMiddleware,
        LiquidationRewardsManager liquidationRewardsManager,
        Usdn usdn
    ) internal {
        _storage._oracleMiddleware = oracleMiddleware;
        uint8 priceFeedDecimals = oracleMiddleware.getDecimals();
        _storage._priceFeedDecimals = priceFeedDecimals;
        _storage._liquidationRewardsManager = liquidationRewardsManager;
        _storage._targetUsdnPrice = uint128(10_087 * 10 ** (priceFeedDecimals - 4)); // $1.0087
        _storage._usdnRebaseThreshold = uint128(1009 * 10 ** (priceFeedDecimals - 3)); // $1.009
        _storage._usdn = usdn;
    }

    function _setFeeCollector(address feeCollector) internal {
        _storage._feeCollector = feeCollector;
    }

    function _setProtocolFallback(address protocolFallback) internal {
        _storage._protocolFallbackAddr = protocolFallback;
    }
}
