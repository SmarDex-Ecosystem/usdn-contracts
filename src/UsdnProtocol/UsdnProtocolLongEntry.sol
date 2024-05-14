// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import {
    Position, PositionId, LongPendingAction, PendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { UsdnProtocolLongLibrary as longLib } from "src/UsdnProtocol/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";

abstract contract UsdnProtocolLongEntry is UsdnProtocolBaseStorage, InitializableReentrancyGuard {
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    /**
     * @notice Structure to hold the temporary data during liquidation
     * @param tempLongBalance The temporary long balance
     * @param tempVaultBalance The temporary vault balance
     * @param currentTick The current tick (tick corresponding to the current asset price)
     * @param iTick Tick iterator index
     * @param totalExpoToRemove The total expo to remove due to the liquidation of some ticks
     * @param accumulatorValueToRemove The value to remove from the liquidation multiplier accumulator, due to the
     * liquidation of some ticks
     * @param longTradingExpo The long trading expo
     * @param currentPrice The current price of the asset
     * @param accumulator The liquidation multiplier accumulator before the liquidation
     */
    struct LiquidationData {
        int256 tempLongBalance;
        int256 tempVaultBalance;
        int24 currentTick;
        int24 iTick;
        uint256 totalExpoToRemove;
        uint256 accumulatorValueToRemove;
        uint256 longTradingExpo;
        uint256 currentPrice;
        HugeUint.Uint512 accumulator;
    }

    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        return longLib.validateActionablePendingActions(s, previousActionsData, maxValidations);
    }

    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 liquidatedPositions_)
    {
        return longLib.liquidate(s, currentPriceData, iterations);
    }

    function maxTick() public view returns (int24 tick_) {
        return longLib.maxTick(s);
    }

    function getLongPosition(PositionId memory posId)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        return longLib.getLongPosition(s, posId);
    }

    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        return longLib.getMinLiquidationPrice(s, price);
    }

    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        return longLib.getPositionValue(s, posId, price, timestamp);
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public view returns (int256 expo_) {
        return longLib.longTradingExpoWithFunding(s, currentPrice, timestamp);
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        return longLib.longAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant returns (PositionId memory posId_) {
        return longLib.initiateOpenPosition(s, amount, desiredLiqPrice, currentPriceData, previousActionsData, to);
    }

    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        return longLib.validateOpenPosition(s, openPriceData, previousActionsData);
    }

    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) public view {
        return longLib._checkImbalanceLimitOpen(s, openTotalExpoValue, openCollatValue);
    }

    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        longLib.initiateClosePosition(s, posId, amountToClose, currentPriceData, previousActionsData, to);
    }

    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        longLib.validateClosePosition(s, closePriceData, previousActionsData);
    }

    function _calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal view returns (uint256 multiplier_) {
        return longLib._calcFixedPrecisionMultiplier(s, assetPrice, longTradingExpo, accumulator);
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        longLib._checkSafetyMargin(s, currentPrice, liquidationPrice);
    }

    function _checkImbalanceLimitClose(uint256 closePosTotalExpoValue, uint256 closeCollatValue) internal view {
        longLib._checkImbalanceLimitClose(s, closePosTotalExpoValue, closeCollatValue);
    }

    function _assetToRemove(uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        internal
        view
        returns (uint256 boundedPosValue_)
    {
        return longLib._assetToRemove(s, priceWithFees, liqPriceWithoutPenalty, posExpo);
    }

    function _convertLongPendingAction(LongPendingAction memory action)
        internal
        pure
        returns (PendingAction memory pendingAction_)
    {
        return longLib._convertLongPendingAction(action);
    }

    function _validateClosePosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        return longLib._validateClosePosition(s, user, priceData);
    }

    function _initiateClosePosition(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (uint256 securityDepositValue_) {
        return longLib._initiateClosePosition(s, user, to, posId, amountToClose, currentPriceData);
    }
}
