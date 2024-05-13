// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { Position, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { IUsdnProtocolLongProxy } from "src/interfaces/UsdnProtocol/IUsdnProtocolLongProxy.sol";

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

    function funding(uint128 timestamp) public returns (int256 fund_, int256 oldLongExpo_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLongProxy.funding.selector, timestamp)
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
                IUsdnProtocolLongProxy.validateActionablePendingActions.selector, previousActionsData, maxValidations
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
            abi.encodeWithSelector(IUsdnProtocolLongProxy.liquidate.selector, currentPriceData, iterations)
        );
        require(success, "failed");
        liquidatedPositions_ = abi.decode(data, (uint256));
    }

    function minTick() public returns (int24 tick_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSelector(IUsdnProtocolLong.minTick.selector, tick_));
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
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
            abi.encodeWithSelector(IUsdnProtocolLongProxy.longTradingExpoWithFunding.selector, currentPrice, timestamp)
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
                IUsdnProtocolLongProxy.longAssetAvailableWithFunding.selector, currentPrice, timestamp
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
                IUsdnProtocolLongProxy.initiateOpenPosition.selector,
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
                IUsdnProtocolLongProxy.validateOpenPosition.selector, openPriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) public {
        (bool success,) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolLongProxy._checkImbalanceLimitOpen.selector, openTotalExpoValue, openCollatValue
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
                IUsdnProtocolLongProxy.initiateClosePosition.selector,
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
                IUsdnProtocolLongProxy.validateClosePosition.selector, closePriceData, previousActionsData
            )
        );
        require(success, "failed");
    }

    function getEffectiveTickForPrice(uint128 price) public returns (int24 tick_) {
        (bool success, bytes memory data) =
        // TO DO : check if we can use selector
         address(s._protocol).delegatecall(abi.encodeWithSignature("getEffectiveTickForPrice(uint128)", price));
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
    }

    function getEffectiveTickForPrice(
        uint128 price,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing
    ) public returns (int24 tick_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            // TO DO : same
            abi.encodeWithSignature(
                "getEffectiveTickForPrice(uint128,uint256,uint256,HugeUint.Uint512,int24",
                price,
                assetPrice,
                longTradingExpo,
                accumulator,
                tickSpacing
            )
        );
        require(success, "failed");
        tick_ = abi.decode(data, (int24));
    }

    function getEffectivePriceForTick(int24 tick) public returns (uint128 price_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSignature("getEffectivePriceForTick(int24)", tick));
        require(success, "failed");
        price_ = abi.decode(data, (uint128));
    }

    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) public returns (uint128 price_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSignature(
                "getEffectivePriceForTick(int24,uint256,uint256,HugeUint.Uint512)",
                tick,
                assetPrice,
                longTradingExpo,
                accumulator
            )
        );
        require(success, "failed");
        price_ = abi.decode(data, (uint128));
    }

    function getTickLiquidationPenalty(int24 tick) public returns (uint8 liquidationPenalty_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolLong.getTickLiquidationPenalty.selector, tick)
        );
        require(success, "failed");
        liquidationPenalty_ = abi.decode(data, (uint8));
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
}
