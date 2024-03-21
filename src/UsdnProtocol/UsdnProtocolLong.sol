// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolVault } from "src/UsdnProtocol/UsdnProtocolVault.sol";
import { UsdnProtocolLib } from "src/libraries/UsdnProtocolLib.sol";

abstract contract UsdnProtocolLong is IUsdnProtocolLong, UsdnProtocolVault {
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @inheritdoc IUsdnProtocolLong
    function minTick() public view returns (int24 tick_) {
        tick_ = UsdnProtocolLib.calcMinTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function maxTick() public view returns (int24 tick_) {
        tick_ = UsdnProtocolLib.calcMaxTick(_tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getLongPosition(int24 tick, uint256 tickVersion, uint256 index)
        public
        view
        returns (Position memory pos_)
    {
        (bytes32 tickHash, uint256 version) = _tickHash(tick);
        if (tickVersion != version) {
            revert UsdnProtocolOutdatedTick(version, tickVersion);
        }
        pos_ = _longPositions[tickHash][index];
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionsInTick(int24 tick) external view returns (uint256 len_) {
        (bytes32 tickHash,) = _tickHash(tick);
        len_ = _positionsInTick[tickHash];
    }

    /// @inheritdoc IUsdnProtocolLong
    // slither-disable-next-line write-after-write
    function getMinLiquidationPrice(uint128 price) public view returns (uint128 liquidationPrice_) {
        liquidationPrice_ = UsdnProtocolLib.calcLiquidationPrice(price, uint128(_minLeverage));
        uint256 liquidationMultiplier = _liquidationMultiplier;
        int24 tickSpacing = _tickSpacing;
        int24 tick = UsdnProtocolLib.calcEffectiveTickForPrice(liquidationPrice_, liquidationMultiplier, tickSpacing);
        liquidationPrice_ = UsdnProtocolLib.calcEffectivePriceForTick(tick + tickSpacing, liquidationMultiplier);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getPositionValue(int24 tick, uint256 tickVersion, uint256 index, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 value_)
    {
        Position memory pos = getLongPosition(tick, tickVersion, index);
        uint256 liquidationMultiplier = getLiquidationMultiplier(timestamp);
        uint128 liqPrice = UsdnProtocolLib.calcEffectivePriceForTick(
            tick - int24(_liquidationPenalty) * _tickSpacing, liquidationMultiplier
        );
        value_ = UsdnProtocolLib.calcPositionValue(price, liqPrice, pos.totalExpo);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectiveTickForPrice(uint128 price) external view returns (int24 tick_) {
        tick_ = UsdnProtocolLib.calcEffectiveTickForPrice(price, _liquidationMultiplier, _tickSpacing);
    }

    /// @inheritdoc IUsdnProtocolLong
    function getEffectivePriceForTick(int24 tick) external view returns (uint128 price_) {
        price_ = UsdnProtocolLib.calcEffectivePriceForTick(tick, _liquidationMultiplier);
    }

    /**
     * @notice Calculate the value of a tick, knowing its contained total expo and the current asset price
     * @param currentPrice The current price of the asset
     * @param tick The tick number
     * @param tickTotalExpo The total expo of the positions in the tick
     */
    function _tickValue(uint256 currentPrice, int24 tick, uint256 tickTotalExpo)
        internal
        view
        returns (int256 value_)
    {
        // value = totalExpo * (currentPrice - liqPriceWithoutPenalty) / currentPrice
        uint128 liqPriceWithoutPenalty = UsdnProtocolLib.calcEffectivePriceForTick(
            tick - int24(_liquidationPenalty) * _tickSpacing, _liquidationMultiplier
        );

        // if the current price is lower than the liquidation price, we have effectively a negative value
        if (currentPrice <= liqPriceWithoutPenalty) {
            // we calculate the inverse and then change the sign
            value_ =
                -int256(UsdnProtocolLib.fullMulDiv(tickTotalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice));
        } else {
            value_ =
                int256(UsdnProtocolLib.fullMulDiv(tickTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice));
        }
    }

    function _maxLiquidationPriceWithSafetyMargin(uint128 price) internal view returns (uint128 maxLiquidationPrice_) {
        maxLiquidationPrice_ = (price * (BPS_DIVISOR - _safetyMarginBps) / BPS_DIVISOR).toUint128();
    }

    function _checkSafetyMargin(uint128 currentPrice, uint128 liquidationPrice) internal view {
        uint128 maxLiquidationPrice = _maxLiquidationPriceWithSafetyMargin(currentPrice);
        if (liquidationPrice >= maxLiquidationPrice) {
            revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
        }
    }

    function _saveNewPosition(int24 tick, Position memory long)
        internal
        returns (uint256 tickVersion_, uint256 index_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = _tickHash(tick);

        // Adjust state
        _balanceLong += long.amount;
        _totalExpo += long.totalExpo;
        _totalExpoByTick[tickHash] += long.totalExpo;
        ++_positionsInTick[tickHash];
        ++_totalLongPositions;

        // Add to tick array
        Position[] storage tickArray = _longPositions[tickHash];
        index_ = tickArray.length;
        if (_positionsInTick[tickHash] == 1) {
            // first position in this tick, we need to reflect that it is populated
            UsdnProtocolLib.setBitmapTick(_tickBitmap, tick, _tickSpacing);
        }
        if (tick > _maxInitializedTick) {
            // keep track of max initialized tick
            _maxInitializedTick = tick;
        }
        tickArray.push(long);
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
        if (amountToRemove < pos.amount) {
            Position storage position = _longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            unchecked {
                --_positionsInTick[tickHash];
                --_totalLongPositions;
            }

            // Remove from tick array (set to zero to avoid shifting indices)
            delete _longPositions[tickHash][index];
            if (_positionsInTick[tickHash] == 0) {
                // we removed the last position in the tick
                UsdnProtocolLib.unsetBitmapTick(_tickBitmap, tick, _tickSpacing);
            }
        }

        _totalExpo -= totalExpoToRemove;
        _totalExpoByTick[tickHash] -= totalExpoToRemove;
    }

    /**
     * @notice Liquidate positions which have a liquidation price lower than the current price
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying PnL and funding
     * @return liquidatedPositions_ The number of positions that were liquidated
     * @return liquidatedTicks_ The number of ticks that were liquidated
     * @return remainingCollateral_ The remaining collateral after handling of the liquidated positions
     * @return newLongBalance_ The new long balance after handling of the remaining collateral or bad debt
     * @return newVaultBalance_ The new vault balance after handling of the remaining collateral or bad debt
     */
    function _liquidatePositions(
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    )
        internal
        returns (
            uint256 liquidatedPositions_,
            uint16 liquidatedTicks_,
            int256 remainingCollateral_,
            uint256 newLongBalance_,
            uint256 newVaultBalance_
        )
    {
        // max iteration limit
        if (iteration > MAX_LIQUIDATION_ITERATION) {
            iteration = MAX_LIQUIDATION_ITERATION;
        }

        int24 currentTick = UsdnProtocolLib.calcClosestTickForPrice(currentPrice, _liquidationMultiplier);
        int24 tick = _maxInitializedTick;

        do {
            {
                int24 tickSpacing = _tickSpacing;
                uint256 index = UsdnProtocolLib.findBitmapLastSet(_tickBitmap, tick, tickSpacing);
                if (index == LibBitmap.NOT_FOUND) {
                    // no populated ticks left
                    break;
                }

                tick = UsdnProtocolLib.bitmapIndexToTick(index, tickSpacing);
                if (tick < currentTick) {
                    break;
                }
            }

            // we have found a non-empty tick that needs to be liquidated
            uint256 tickTotalExpo;
            {
                (bytes32 tickHash,) = _tickHash(tick);
                tickTotalExpo = _totalExpoByTick[tickHash];
                uint256 length = _positionsInTick[tickHash];
                unchecked {
                    _totalExpo -= tickTotalExpo;

                    _totalLongPositions -= length;
                    liquidatedPositions_ += length;

                    ++_tickVersion[tick];
                    ++liquidatedTicks_;
                }
            }

            {
                int256 tickValue = _tickValue(currentPrice, tick, tickTotalExpo);
                remainingCollateral_ += tickValue;

                UsdnProtocolLib.unsetBitmapTick(_tickBitmap, tick, _tickSpacing);

                emit LiquidatedTick(
                    tick,
                    _tickVersion[tick] - 1,
                    currentPrice,
                    UsdnProtocolLib.calcEffectivePriceForTick(tick, _liquidationMultiplier),
                    tickValue
                );
            }
        } while (liquidatedTicks_ < iteration);

        if (liquidatedPositions_ != 0) {
            if (tick < currentTick) {
                // all ticks above the current tick were liquidated
                _maxInitializedTick = UsdnProtocolLib.findMaxInitializedTick(_tickBitmap, currentTick, _tickSpacing);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                _maxInitializedTick = UsdnProtocolLib.findMaxInitializedTick(_tickBitmap, tick, _tickSpacing);
            }
        }

        // Transfer remaining collateral to vault or pay bad debt
        tempVaultBalance += remainingCollateral_;
        tempLongBalance -= remainingCollateral_;

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

        newLongBalance_ = tempLongBalance.toUint256();
        newVaultBalance_ = tempVaultBalance.toUint256();
    }
}
