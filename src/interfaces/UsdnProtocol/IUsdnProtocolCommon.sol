// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { HugeUint } from "src/libraries/HugeUint.sol";
import {
    ProtocolAction,
    PreviousActionsData,
    PendingAction,
    TickData,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    LiquidationsEffects,
    Position
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolCommon {
    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        external
        returns (int256);

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) external returns (int24 tick_);

    function getEffectiveTickForPrice(uint128 price) external returns (int24 tick_);

    function getTickLiquidationPenalty(int24 tick) external returns (uint8 liquidationPenalty_);

    function getEffectivePriceForTick(int24 tick) external returns (uint128 price_);

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external returns (uint128 price_);

    function minTick() external returns (int24 tick_);

    function _getOraclePrice(ProtocolAction action, uint256 timestamp, bytes calldata priceData)
        external
        returns (PriceInfo memory price_);

    function _unadjustPrice(
        uint256 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) external returns (uint256 unadjustedPrice_);

    function _calcTickWithoutPenalty(int24 tick, uint8 liquidationPenalty) external returns (int24 tick_);

    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        external
        returns (uint256 assetExpected_);

    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        external
        view
        returns (uint256 toMint_);

    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) external view returns (uint128 price_);

    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        external
        pure
        returns (uint256 usdnShares_);

    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore)
        external
        payable;

    function _executePendingActionOrRevert(PreviousActionsData calldata data)
        external
        returns (uint256 securityDepositValue_);

    function _executePendingAction(PreviousActionsData calldata data)
        external
        returns (bool success_, bool executed_, uint256 securityDepositValue_);

    function _getPendingAction(address user) external view returns (PendingAction memory action_, uint128 rawIndex_);

    function _addPendingAction(address user, PendingAction memory action)
        external
        returns (uint256 securityDepositValue_);

    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        external
        view
        returns (uint256 totalSupply_);

    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        external
        view
        returns (uint256 price_);

    function _usdnRebase(uint128 assetPrice, bool ignoreInterval) external returns (bool rebased_);

    function _updateEMA(uint128 secondsElapsed) external returns (int256);

    function _calcBitmapIndexFromTick(int24 tick) external view returns (uint256 index_);

    function _findHighestPopulatedTick(int24 searchStart) external view returns (int24 tick_);

    function _calcTickFromBitmapIndex(uint256 index, int24 tickSpacing) external pure returns (int24 tick_);

    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) external view returns (uint128 leverage_);

    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) external view returns (uint128 price_);

    function _longAssetAvailable(uint128 currentPrice) external view returns (int256 available_);

    function _tickHash(int24 tick) external view returns (bytes32 hash_, uint256 version_);

    function _tickValue(
        int24 tick,
        uint256 currentPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        TickData memory tickData
    ) external view returns (int256 value_);

    function _convertDepositPendingAction(DepositPendingAction memory action)
        external
        pure
        returns (PendingAction memory pendingAction_);

    function _toDepositPendingAction(PendingAction memory action)
        external
        pure
        returns (DepositPendingAction memory vaultAction_);

    function _toWithdrawalPendingAction(PendingAction memory action)
        external
        pure
        returns (WithdrawalPendingAction memory vaultAction_);

    function _toLongPendingAction(PendingAction memory action)
        external
        pure
        returns (LongPendingAction memory longAction_);

    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) external returns (LiquidationsEffects memory effects_);

    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp)
        external
        returns (bool priceUpdated_, int256 tempLongBalance_, int256 tempVaultBalance_);

    function _getActionablePendingAction() external returns (PendingAction memory action_, uint128 rawIndex_);

    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        external
        pure
        returns (int256 value_);

    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) external;

    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) external pure returns (int256 available_);

    function _calcTickFromBitmapIndex(uint256 index) external view returns (int24 tick_);

    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) external pure returns (uint256 index_);
}
