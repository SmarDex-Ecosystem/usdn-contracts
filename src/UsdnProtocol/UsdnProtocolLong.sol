// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { Position, LiquidationsEffects, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolVault } from "src/UsdnProtocol/UsdnProtocolVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";

abstract contract UsdnProtocolLong is IUsdnProtocolLong, UsdnProtocolVault {
    using SafeERC20 for IERC20Metadata;
    using LibBitmap for LibBitmap.Bitmap;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    /// @inheritdoc IUsdnProtocolLong
    function minTick() public view returns (int24 tick_) {
        tick_ = TickMath.minUsableTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function maxTick() public view returns (int24 tick_) {
        tick_ = TickMath.maxUsableTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPosition(int24 tick, uint256 tickVersion, uint256 index)
        public
        view
        returns (Position memory pos_, uint8 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = _tickHash(tick);
        if (tickVersion != version) {
            revert UsdnProtocolOutdatedTick(version, tickVersion);
        }
        pos_ = _longPositions[tickHash][index];
        liquidationPenalty_ = _tickData[tickHash].liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolLong
    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = _getLiquidationPrice(price, uint128(_minLeverage));
        int24 tick = getEffectiveTickForPrice(liquidationPrice_);
        liquidationPrice_ = getEffectivePriceForTick(tick + _tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(int24 tick, uint256 tickVersion, uint256 index, uint128 price, uint128 timestamp)
        external
        view
        returns (int256 value_)
    {
        (Position memory pos, uint8 liquidationPenalty) = getLongPosition(tick, tickVersion, index);
        uint256 liquidationMultiplier = getLiquidationMultiplier(timestamp);
        uint128 liqPrice =
            getEffectivePriceForTick(tick - int24(uint24(liquidationPenalty)) * _tickSpacing, liquidationMultiplier);
        value_ = _positionValue(price, liqPrice, pos.totalExpo);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) public view returns (int24 tick_) {
        tick_ = getEffectiveTickForPrice(price, _liquidationMultiplier);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price, uint256 liqMultiplier) public view returns (int24 tick_) {
        // adjusted price with liquidation multiplier
        uint256 priceWithMultiplier =
            FixedPointMathLib.fullMulDiv(price, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS, liqMultiplier);

        if (priceWithMultiplier < TickMath.MIN_PRICE) {
            return minTick();
        }

        int24 tickSpacing = _tickSpacing;
        tick_ = TickMath.getTickAtPrice(priceWithMultiplier);

        // round down to the next valid tick according to _tickSpacing (towards negative infinity)
        if (tick_ < 0) {
            // we round up the inverse number (positive) then invert it -> round towards negative infinity
            tick_ = -int24(int256(FixedPointMathLib.divUp(uint256(int256(-tick_)), uint256(int256(tickSpacing)))))
                * tickSpacing;
            // avoid invalid ticks
            int24 minUsableTick = minTick();
            if (tick_ < minUsableTick) {
                tick_ = minUsableTick;
            }
        } else {
            // rounding is desirable here
            // slither-disable-next-line divide-before-multiply
            tick_ = (tick_ / tickSpacing) * tickSpacing;
        }
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(int24 tick) public view returns (uint128 price_) {
        // adjusted price with liquidation multiplier
        price_ = getEffectivePriceForTick(tick, _liquidationMultiplier);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) public pure returns (uint128 price_) {
        // adjusted price with liquidation multiplier
        price_ = FixedPointMathLib.fullMulDiv(
            TickMath.getPriceAtTick(tick), liqMultiplier, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
    }

    /**
     * @notice Find the largest tick which contains at least one position
     * @param searchStart The tick from which to start searching
     */
    function _findMaxInitializedTick(int24 searchStart) internal view returns (int24 tick_) {
        uint256 index = _tickBitmap.findLastSet(_tickToBitmapIndex(searchStart));
        if (index == LibBitmap.NOT_FOUND) {
            tick_ = minTick();
        } else {
            tick_ = _bitmapIndexToTick(index);
        }
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    /**
     * @notice Calculate the value of a position, knowing its liquidation price and the current asset price
     * @param currentPrice The current price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @return value_ The value of the position. If the current price is smaller than the liquidation price without
     * penalty, then the position value is negative (bad debt)
     */
    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
        internal
        pure
        returns (int256 value_)
    {
        if (currentPrice < liqPriceWithoutPenalty) {
            value_ = -FixedPointMathLib.fullMulDiv(positionTotalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
                .toInt256();
        } else {
            value_ = FixedPointMathLib.fullMulDiv(
                positionTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice
            ).toInt256();
        }
    }

    /**
     * @notice Calculate the value of a tick, knowing its contained total expo and the current asset price
     * @param currentPrice The current price of the asset
     * @param tick The tick number
     * @param tickData The aggregate data for the tick
     */
    function _tickValue(uint256 currentPrice, int24 tick, TickData memory tickData)
        internal
        view
        returns (int256 value_)
    {
        // value = totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice
        uint128 liqPriceWithoutPenalty =
            getEffectivePriceForTick(tick - int24(uint24(tickData.liquidationPenalty)) * _tickSpacing);

        // if the current price is lower than the liquidation price, we have effectively a negative value
        if (currentPrice <= liqPriceWithoutPenalty) {
            // we calculate the inverse and then change the sign
            value_ = -int256(
                FixedPointMathLib.fullMulDiv(tickData.totalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
            );
        } else {
            value_ = int256(
                FixedPointMathLib.fullMulDiv(tickData.totalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice)
            );
        }
    }

    /// @dev This does not take into account the liquidation penalty
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint128 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // Also, calculation below would underflow
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = ((10 ** LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice)).toUint128();
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
     */
    function _calculatePositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        internal
        pure
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
    }

    /**
     * @notice Calculate the collateral amount a position needs to reach the provided total expo.
     * @dev Reverts when startPrice <= liquidationPrice
     * @param totalExpo The total expo to reach
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return amount_ The collateral amount a position needs to reach the total expo
     */
    function _calcPositionAmount(uint128 totalExpo, uint128 startPrice, uint128 liquidationPrice)
        internal
        pure
        returns (uint128 amount_)
    {
        if (startPrice <= liquidationPrice) {
            revert UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        amount_ = FixedPointMathLib.fullMulDiv(totalExpo, startPrice - liquidationPrice, startPrice).toUint128();
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = (currentPrice * (BPS_DIVISOR - _safetyMarginBps) / BPS_DIVISOR).toUint128();
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function _saveNewPosition(int24 tick, Position memory long, uint8 liquidationPenalty)
        internal
        returns (uint256 tickVersion_, uint256 index_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = _tickHash(tick);

        // Add to tick array
        Position[] storage tickArray = _longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > _maxInitializedTick) {
            // keep track of max initialized tick
            _maxInitializedTick = tick;
        }
        tickArray.push(long);

        // Adjust state
        _balanceLong += long.amount;
        _totalExpo += long.totalExpo;
        ++_totalLongPositions;
        TickData storage tickData = _tickData[tickHash];
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            _tickBitmap.set(_tickToBitmapIndex(tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's liquidationPenalty since it remains constant
        }
    }

    /**
     * @notice Remove the provided total amount from its position and update the position, tick and protocol's balances.
     * If the amount to remove is greater or equal than the position's, the position is deleted instead.
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     */
    function _removeAmountFromPosition(
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) internal {
        (bytes32 tickHash,) = _tickHash(tick);
        TickData storage tickData = _tickData[tickHash];
        if (amountToRemove < pos.amount) {
            Position storage position = _longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            tickData.totalPos -= 1;
            --_totalLongPositions;

            // Remove from tick array (set to zero to avoid shifting indices)
            delete _longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                _tickBitmap.unset(_tickToBitmapIndex(tick));
            }
        }

        _totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
    }

    /// @inheritdoc IUsdnProtocolLong
    function getTickLiquidationPenalty(int24 tick) public view returns (uint8 liquidationPenalty_) {
        (bytes32 tickHash,) = _tickHash(tick);
        liquidationPenalty_ = _getTickLiquidationPenalty(tickHash);
    }

    /**
     * @notice Retrieve the liquidation penalty assigned to the tick and version corresponding to `tickHash`, if there
     * are positions in it, otherwise retrieve the current setting value from storage.
     * @dev This method allows to re-use a pre-computed tickHash if available
     * @param tickHash The tick hash
     * @return liquidationPenalty_ The liquidation penalty, in tick spacing units
     */
    function _getTickLiquidationPenalty(bytes32 tickHash) internal view returns (uint8 liquidationPenalty_) {
        TickData storage tickData = _tickData[tickHash];
        liquidationPenalty_ = tickData.totalPos != 0 ? tickData.liquidationPenalty : _liquidationPenalty;
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @return index_ The index into the Bitmap
     */
    function _tickToBitmapIndex(int24 tick) internal view returns (uint256 index_) {
        int24 compactTick = tick / _tickSpacing;
        // shift into positive and cast to uint256
        index_ = uint256(int256(compactTick) - int256(type(int24).min));
    }

    /**
     * @dev Convert a Bitmap index to a signed tick
     * @param index The index into the Bitmap
     * @return tick_ The tick corresponding to the index, a multiple of `tickSpacing`
     */
    function _bitmapIndexToTick(uint256 index) internal view returns (int24 tick_) {
        // cast to int256 and shift into negative
        int24 compactTick = (int256(index) + int256(type(int24).min)).toInt24();
        tick_ = compactTick * _tickSpacing;
    }

    /**
     * @notice Check if there are orders in the liquidated tick and create a position using the amount available if so.
     * @param currentPrice The current price
     * @param liquidatedTickHash The tick hash of the liquidated tick
     * @param liquidatedTickTotalExpo The total expo of the liquidated tick
     * @param tempLongBalance The temporary long balance as calculated when applying PnL and funding
     * @return newTempLongBalance_ The new long balance after handling the order manager position
     */
    function _saveOrderManagerPositionInTick(
        uint128 currentPrice,
        bytes32 liquidatedTickHash,
        uint128 liquidatedTickTotalExpo,
        int256 tempLongBalance
    ) internal returns (int256 newTempLongBalance_) {
        address orderManagerAddress = address(_orderManager);
        // If the order manager is not set, return;
        if (orderManagerAddress == address(0)) {
            return tempLongBalance;
        }

        uint128 amountTaken;
        int24 liquidationTick;
        {
            uint256 amountAvailable;
            // Get the amount available in orders in the tick
            (liquidationTick, amountAvailable) = _orderManager.fulfillOrdersInTick(currentPrice, liquidatedTickHash);

            // If there are no orders for this tick, return
            if (amountAvailable == 0) {
                return tempLongBalance;
            }

            amountTaken = amountAvailable.toUint128();
        }

        // Calculate the total expo available to not imbalance the protocol
        uint128 posTotalExpo;
        {
            // Calculate liquidation price without the liquidation penalty for the tick
            uint128 liqPriceWithoutPenalty =
                getEffectivePriceForTick(liquidationTick - int24(_liquidationPenalty) * _tickSpacing);
            posTotalExpo = _calculatePositionTotalExpo(amountTaken, currentPrice, liqPriceWithoutPenalty);

            // If the total expo of the liquidated tick is lower than the order manager's position total expo
            // Lower the position size to the liquidated tick's total expo
            if (liquidatedTickTotalExpo < posTotalExpo) {
                posTotalExpo = liquidatedTickTotalExpo;
                amountTaken = _calcPositionAmount(liquidatedTickTotalExpo, currentPrice, liqPriceWithoutPenalty);
            }
        }

        // Create the position
        uint256 tickVersion;
        uint256 index;
        {
            Position memory pos = Position({
                timestamp: uint40(block.timestamp),
                user: orderManagerAddress,
                totalExpo: posTotalExpo,
                amount: amountTaken
            });

            (tickVersion, index) = _saveNewPosition(liquidationTick, pos);

            // Transfer assets from the order manager to the protocol
            _asset.safeTransferFrom(orderManagerAddress, address(this), amountTaken);
        }

        // Update the vault/long balances
        // Safe cast as type(uint128).max is lower than type(int256).max
        newTempLongBalance_ = tempLongBalance + int256(uint256(amountTaken));

        emit OrderManagerPositionOpened(
            orderManagerAddress,
            uint40(block.timestamp),
            _orderManager.getOrdersLeverage().toUint128(),
            amountTaken,
            currentPrice,
            liquidationTick,
            tickVersion,
            index
        );
    }

    /**
     * @notice Liquidate positions which have a liquidation price lower than the current price
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying PnL and funding
     * @return effects_ The effects of the liquidations on the protocol
     */
    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) internal returns (LiquidationsEffects memory effects_) {
        // max iteration limit
        if (iteration > MAX_LIQUIDATION_ITERATION) {
            iteration = MAX_LIQUIDATION_ITERATION;
        }

        int24 currentTick = TickMath.getClosestTickAtPrice(
            FixedPointMathLib.fullMulDiv(currentPrice, 10 ** LIQUIDATION_MULTIPLIER_DECIMALS, _liquidationMultiplier)
        );
        int24 tick = _maxInitializedTick;

        do {
            {
                uint256 index = _tickBitmap.findLastSet(_tickToBitmapIndex(tick));
                if (index == LibBitmap.NOT_FOUND) {
                    // no populated ticks left
                    break;
                }

                tick = _bitmapIndexToTick(index);
                if (tick < currentTick) {
                    break;
                }
            }

            // we have found a non-empty tick that needs to be liquidated
            TickData memory tickData;
            {
                (bytes32 tickHash,) = _tickHash(tick);
                tickData = _tickData[tickHash];
                _totalExpo -= tickData.totalExpo;
                _totalLongPositions -= tickData.totalPos;
                effects_.liquidatedPositions += tickData.totalPos;

                ++_tickVersion[tick];
                ++effects_.liquidatedTicks;

                tempLongBalance = _saveOrderManagerPositionInTick(
                    currentPrice.toUint128(), tickHash, tickTotalExpo.toUint128(), tempLongBalance
                );
            }

            {
                int256 tickValue = _tickValue(currentPrice, tick, tickData);
                effects_.remainingCollateral += tickValue;

                _tickBitmap.unset(_tickToBitmapIndex(tick));

                emit LiquidatedTick(
                    tick, _tickVersion[tick] - 1, currentPrice, getEffectivePriceForTick(tick), tickValue
                );
            }
        } while (effects_.liquidatedTicks < iteration);

        if (effects_.liquidatedPositions != 0) {
            if (tick < currentTick) {
                // all ticks above the current tick were liquidated
                _maxInitializedTick = _findMaxInitializedTick(currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                _maxInitializedTick = _findMaxInitializedTick(tick);
            }
        }

        // Transfer remaining collateral to vault or pay bad debt
        tempVaultBalance += effects_.remainingCollateral;
        tempLongBalance -= effects_.remainingCollateral;

        // This can happen if the funding is larger than the remaining balance in the long side after applying PnL.
        // Test case: test_assetToTransferZeroBalance()
        if (tempLongBalance < 0) {
            tempVaultBalance += tempLongBalance;
            tempLongBalance = 0;
        }

        // This can happen if there is not enough balance in the vault to pay the bad debt of the long side, for
        // example if the protocol fees reduce the vault balance.
        // Test case: test_funding_NegLong_ZeroVault()
        if (tempVaultBalance < 0) {
            tempLongBalance += tempVaultBalance;
            tempVaultBalance = 0;
        }

        effects_.newLongBalance = tempLongBalance.toUint256();
        effects_.newVaultBalance = tempVaultBalance.toUint256();
    }
}
