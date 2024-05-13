// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import {
    Position, PositionId, LongPendingAction, PendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolCommonEntry } from "src/UsdnProtocol/UsdnProtocolCommonEntry.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolLongImplementation } from "src/interfaces/UsdnProtocol/IUsdnProtocolLongImplementation.sol";

abstract contract UsdnProtocolLongEntry is UsdnProtocolCommonEntry {
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

    function funding(uint128 timestamp) public returns (int256 fund_, int256 oldLongExpo_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLongImplementation.funding.selector, timestamp)
        );
        require(success, "failed");
        (fund_, oldLongExpo_) = abi.decode(data, (int256, int256));
    }

    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 validatedActions_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.validateActionablePendingActions.selector,
                previousActionsData,
                maxValidations
            )
        );
        require(success, "failed");
        validatedActions_ = abi.decode(data, (uint256));
    }

    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        initializedAndNonReentrant
        returns (uint256 liquidatedPositions_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLongImplementation.liquidate.selector, currentPriceData, iterations)
        );
        require(success, "failed");
        liquidatedPositions_ = abi.decode(data, (uint256));
    }

    function maxTick() public returns (int24 tick_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSelector(IUsdnProtocolLong.maxTick.selector, tick_));
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
    }

    function getLongPosition(PositionId memory posId)
        public
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSelector(IUsdnProtocolLong.getLongPosition.selector, posId));
        require(success, "failed");
        (pos_, liquidationPenalty_) = abi.decode(data, (Position, uint8));
    }

    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public returns (uint128 liquidationPrice_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLong.getMinLiquidationPrice.selector, price)
        );
        require(success, "failed");
        liquidationPrice_ = abi.decode(data, (uint128));
    }

    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        returns (int256 value_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLong.getPositionValue.selector, posId, price, timestamp)
        );
        require(success, "failed");
        value_ = abi.decode(data, (int256));
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public returns (int256 expo_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.longTradingExpoWithFunding.selector, currentPrice, timestamp
            )
        );
        require(success, "failed");
        expo_ = abi.decode(data, (int256));
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        returns (int256 available_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.longAssetAvailableWithFunding.selector, currentPrice, timestamp
            )
        );
        require(success, "failed");
        available_ = abi.decode(data, (int256));
    }

    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant returns (PositionId memory posId_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.initiateOpenPosition.selector,
                amount,
                desiredLiqPrice,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        require(success, "failed");
        posId_ = abi.decode(data, (PositionId));
    }

    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.validateOpenPosition.selector, openPriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) public {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation._checkImbalanceLimitOpen.selector, openTotalExpoValue, openCollatValue
            )
        );
        require(success, "failed");
    }

    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.initiateClosePosition.selector,
                posId,
                amountToClose,
                currentPriceData,
                previousActionsData,
                to
            )
        );
        require(success, "failed");
    }

    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation.validateClosePosition.selector, closePriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function _calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        // TO DO : make this internal
        public
        returns (uint128 totalExpo_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLong._calculatePositionTotalExpo.selector, amount, startPrice, liquidationPrice
            )
        );
        require(success, "failed");
        totalExpo_ = abi.decode(data, (uint128));
    }

    function _saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        internal
        returns (uint256 tickVersion_, uint256 index_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLong._saveNewPosition.selector, tick, long, liquidationPenalty)
        );
        require(success, "failed");
        (tickVersion_, index_) = abi.decode(data, (uint256, uint256));
    }

    function _calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal returns (uint256 multiplier_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation._calcFixedPrecisionMultiplier.selector,
                assetPrice,
                longTradingExpo,
                accumulator
            )
        );
        require(success, "failed");
        return abi.decode(data, (uint256));
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation._checkSafetyMargin.selector, currentPrice, liquidationPrice
            )
        );
        require(success, "failed");
    }

    function _checkImbalanceLimitClose(uint256 closePosTotalExpoValue, uint256 closeCollatValue) internal {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation._checkImbalanceLimitClose.selector,
                closePosTotalExpoValue,
                closeCollatValue
            )
        );
        require(success, "failed");
    }

    function _assetToRemove(uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        internal
        returns (uint256 boundedPosValue_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation._assetToRemove.selector, priceWithFees, liqPriceWithoutPenalty, posExpo
            )
        );
        require(success, "failed");
        boundedPosValue_ = abi.decode(data, (uint256));
    }

    function _convertLongPendingAction(LongPendingAction memory action)
        internal
        returns (PendingAction memory pendingAction_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLongImplementation._convertLongPendingAction.selector, action)
        );
        require(success, "failed");
        pendingAction_ = abi.decode(data, (PendingAction));
    }

    function _validateClosePosition(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLongImplementation._validateClosePosition.selector, user, priceData)
        );
        require(success, "failed");
        securityDepositValue_ = abi.decode(data, (uint256));
    }

    function _initiateClosePosition(
        address user,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (uint256 securityDepositValue_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongImplementation._initiateClosePosition.selector,
                user,
                to,
                posId,
                amountToClose,
                currentPriceData
            )
        );
        require(success, "failed");
        securityDepositValue_ = abi.decode(data, (uint256));
    }
}
