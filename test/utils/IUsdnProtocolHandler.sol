// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { UsdnProtocolActionsVaultLibrary as ActionsVault } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolActionsVaultLibrary.sol";
import { PriceInfo } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../src/libraries/HugeUint.sol";
import { UsdnProtocolHandler } from "../unit/UsdnProtocol/utils/Handler.sol";

/**
 * @title IUsdnProtocolHandler
 * @notice Interface for the USDN protocol handler
 */
interface IUsdnProtocolHandler is IUsdnProtocol {
    function resetEMA() external;

    function queuePushFront(PendingAction memory action) external returns (uint128 rawIndex_);

    function queueEmpty() external view returns (bool);

    function getQueueItem(uint128 rawIndex) external view returns (PendingAction memory);

    function mockLiquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidatedPositions_);

    function tickValue(int24 tick, uint256 currentPrice) external view returns (int256);

    function emptyVault() external;

    function updateBalances(uint128 currentPrice) external;

    function removePendingAction(uint128 rawIndex, address user) external;

    function i_createWithdrawalPendingAction(
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        ActionsVault.WithdrawalData memory data
    ) external returns (uint256 amountToRefund_);

    function i_createDepositPendingAction(
        address validator,
        address to,
        uint64 securityDepositValue,
        uint128 amount,
        ActionsVault.InitiateDepositData memory data
    ) external returns (uint256 amountToRefund_);

    function i_createOpenPendingAction(
        address to,
        address validator,
        uint64 securityDepositValue,
        InitiateOpenPositionData memory data
    ) external returns (uint256 amountToRefund_);

    function i_createClosePendingAction(
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        ClosePositionData memory data
    ) external returns (uint256 amountToRefund_);

    function findLastSetInTickBitmap(int24 searchFrom) external view returns (uint256 index);

    function tickBitmapStatus(int24 tick) external view returns (bool isSet_);

    function setTickVersion(int24 tick, uint256 version) external;

    function setPendingProtocolFee(uint256 value) external;

    function getLongTradingExpo(uint128 currentPrice) external view returns (int256 expo_);

    function calcEMA(int256 lastFundingPerDay, uint128 secondsElapsed) external view returns (int256);

    function i_initiateClosePosition(Types.InititateClosePositionParams memory params, bytes calldata currentPriceData)
        external
        returns (uint256 securityDepositValue_, bool isLiquidationPending_, bool liq_);

    function i_validateOpenPosition(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_);

    function i_validateClosePosition(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_);

    function i_validateWithdrawal(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_);

    function i_validateDeposit(address user, bytes calldata priceData)
        external
        returns (uint256 securityDepositValue_, bool isValidated_);

    function i_removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) external returns (HugeUint.Uint512 memory liqMultiplierAccumulator_);

    function i_positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (int256 value_);

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_);

    function i_getActionablePendingAction() external returns (PendingAction memory, uint128);

    function i_lastFundingPerDay() external view returns (int256);

    function i_applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        external
        returns (ApplyPnlAndFundingData memory data_);

    function i_liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) external returns (LiquidationsEffects memory effects_);

    function i_toDepositPendingAction(PendingAction memory action)
        external
        pure
        returns (DepositPendingAction memory);

    function i_toWithdrawalPendingAction(PendingAction memory action)
        external
        pure
        returns (WithdrawalPendingAction memory);

    function i_toLongPendingAction(PendingAction memory action) external pure returns (LongPendingAction memory);

    function i_convertDepositPendingAction(DepositPendingAction memory action)
        external
        pure
        returns (PendingAction memory);

    function i_convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        external
        pure
        returns (PendingAction memory);

    function i_convertLongPendingAction(LongPendingAction memory action) external pure returns (PendingAction memory);

    function i_assetToRemove(uint256 balanceLong, uint128 price, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        external
        view
        returns (uint256);

    function i_tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) external view returns (int256);

    function i_getOraclePrice(ProtocolAction action, uint256 timestamp, bytes32 actionId, bytes calldata priceData)
        external
        payable
        returns (PriceInfo memory);

    function i_calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) external pure returns (uint256);

    function i_vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_);

    function i_vaultAssetAvailable(uint128 currentPrice) external view returns (int256);

    function i_tickHash(int24 tick) external view returns (bytes32, uint256);

    function i_longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        external
        pure
        returns (int256 available_);

    function i_longAssetAvailable(uint128 currentPrice) external view returns (int256);

    function i_getLiquidationPrice(uint128 startPrice, uint128 leverage) external pure returns (uint128);

    function i_checkImbalanceLimitDeposit(uint256 depositValue) external view;

    function i_checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) external view;

    function i_checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) external view;

    function i_checkImbalanceLimitClose(uint256 posTotalExpoToClose, uint256 posValueToCloseAfterFees, uint256 fees)
        external
        view;

    function i_getLeverage(uint128 price, uint128 liqPrice) external pure returns (uint256);

    function i_calcTickFromBitmapIndex(uint256 index) external view returns (int24);

    function i_calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) external pure returns (int24);

    function i_calcBitmapIndexFromTick(int24 tick) external view returns (uint256);

    function i_calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) external pure returns (uint256);

    function i_calcLiqPriceFromTradingExpo(uint128 currentPrice, uint128 amount, uint256 tradingExpo)
        external
        pure
        returns (uint128 liqPrice_);

    function i_findHighestPopulatedTick(int24 searchStart) external view returns (int24 tick_);

    function i_updateEMA(int256 fundingPerDay, uint128 secondsElapsed) external;

    function i_usdnRebase(uint128 assetPrice, bool ignoreInterval) external returns (bool, bytes memory);

    function i_calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        external
        pure
        returns (uint256);

    function i_calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        external
        pure
        returns (uint256);

    function i_addPendingAction(address user, PendingAction memory action) external returns (uint256);

    function i_getPendingAction(address user) external view returns (PendingAction memory, uint128);

    function i_getPendingActionOrRevert(address user) external view returns (PendingAction memory, uint128);

    function i_executePendingAction(PreviousActionsData calldata data) external returns (bool, bool, bool, uint256);

    function i_getUsdValueFromShares(uint256 amount, uint128 price, uint256 totalShares, uint256 vaultBalance)
        external
        pure
        returns (uint256);

    function i_getSharesFromUsdValue(uint256 amount, uint128 price, uint256 totalShares, uint256 vaultBalance)
        external
        pure
        returns (uint256);

    function i_getSharesFromSdex(uint256 amount, uint128 price, uint256 totalShares, uint256 vaultBalance)
        external
        pure
        returns (uint256);

    function i_calcSdex(uint128 price, uint256 amount, uint256 totalShares, uint256 vaultBalance)
        external
        pure
        returns (uint256);

    function i_calculateEma(uint256 currentPrice, uint256 vaultBalance, uint256 usdnTotalShares)
        external
        view
        returns (uint256);

    function i_mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB) external pure returns (uint256);

    function i_getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external pure returns (uint128);

    function i_getEffectiveTickForPrice(uint128 price, uint256 liqMultiplier, int24 tickSpacing)
        external
        pure
        returns (int24);

    function i_calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256);

    function i_calcWithdrawalAmountLSB(uint152 usdnShares) external pure returns (uint24);

    function i_calcWithdrawalAmountMSB(uint152 usdnShares) external pure returns (uint128);

    function i_executePendingActionOrRevert(PreviousActionsData calldata data) external;

    function i_prepareInitiateDepositData(address validator, uint128 amount, bytes calldata currentPriceData)
        external
        returns (ActionsVault.InitiateDepositData memory data_);

    function i_prepareWithdrawalData(address validator, uint152 usdnShares, bytes calldata currentPriceData)
        external
        returns (ActionsVault.WithdrawalData memory data_);

    function i_refundEther(uint256 amount, address payable to) external payable;

    function i_refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        external
        payable;

    function i_funding(UsdnProtocolHandler.FundingStorage memory fundingStorage, uint128 timestamp, int256 ema)
        external
        returns (int256 funding_, int256 fundingPerDay_, int256 oldLongExpo_);

    function i_createInitialDeposit(uint128 amount, uint128 price) external;

    function i_createInitialPosition(uint128 amount, uint128 price, int24 tick, uint128 positionTotalExpo) external;

    function i_checkPendingFee() external;

    function i_sendRewardsToLiquidator(
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        bool rebalancerTriggered,
        ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) external;

    function i_prepareClosePositionData(
        address owner,
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        uint256 userMinPrice,
        bytes calldata currentPriceData
    ) external returns (ClosePositionData memory data_, bool liquidated_);

    function i_prepareValidateOpenPositionData(PendingAction memory pending, bytes calldata priceData)
        external
        returns (ValidateOpenPositionData memory data_, bool liquidated_);

    function i_checkInitiateClosePosition(
        address owner,
        address to,
        address validator,
        uint128 amountToClose,
        Position memory pos
    ) external view;

    function i_calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares, uint256 feeBps)
        external
        pure
        returns (uint256 assetExpected_);

    function i_calcTickWithoutPenalty(int24 tick, uint24 liquidationPenalty) external view returns (int24);

    function i_calcTickWithoutPenalty(int24 tick) external view returns (int24);

    function i_unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external pure returns (uint256);
    function i_clearPendingAction(address user, uint128 rawIndex) external;

    function i_calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_);
    function i_calcImbalanceOpenBps(int256 vaultBalance, int256 longBalance, uint256 longTotalExpo)
        external
        pure
        returns (int256 imbalanceBps_);

    function i_removeBlockedPendingAction(uint128 rawIndex, address payable to, bool cleanup) external;

    function i_checkInitImbalance(uint128 positionTotalExpo, uint128 longAmount, uint128 depositAmount) external view;

    function i_removeStalePendingAction(address user) external returns (uint256);

    function i_calcRebalancerPositionTick(
        uint128 neutralPrice,
        uint128 positionAmount,
        uint256 rebalancerMaxLeverage,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        HugeUint.Uint512 memory liqMultiplierAccumulator
    ) external view returns (int24 tickWithoutLiqPenalty_);

    function i_saveNewPosition(int24 tick, Position memory long, uint24 liquidationPenalty)
        external
        returns (uint256, uint256, HugeUint.Uint512 memory);

    function i_checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) external view;

    function i_calculateFee(int256 fundAsset) external returns (int256 fee_, int256 fundAssetWithFee_);

    function i_flashClosePosition(
        PositionId memory posId,
        uint128 neutralPrice,
        uint256 totalExpo,
        uint256 balanceLong,
        uint256 balanceVault,
        HugeUint.Uint512 memory liqMultiplierAccumulator
    ) external returns (int256 positionValue_);

    function i_flashOpenPosition(
        address user,
        uint128 neutralPrice,
        int24 tick,
        uint128 posTotalExpo,
        uint24 liquidationPenalty,
        uint128 amount
    ) external returns (PositionId memory posId_);

    function i_triggerRebalancer(
        uint128 lastPrice,
        uint256 longBalance,
        uint256 vaultBalance,
        int256 remainingCollateral
    ) external returns (uint256 longBalance_, uint256 vaultBalance_);

    function i_fundingAsset(uint128 timestamp, int256 ema)
        external
        view
        returns (int256 fundingAsset, int256 fundingPerDay);

    function i_fundingPerDay(int256 ema) external view returns (int256 fundingPerDay_, int256 oldLongExpo_);

    function i_protocolFeeBps() external view returns (int256);

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_);

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 liqMultiplier,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_);
}
