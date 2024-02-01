// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";

abstract contract UsdnProtocolActions is UsdnProtocolLong {
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using LibBitmap for LibBitmap.Bitmap;

    /**
     * @dev The minimum total supply of USDN that we allow.
     * Upon the first deposit, this amount is sent to the dead address and cannot be later recovered.
     */
    uint256 public constant MIN_USDN_SUPPLY = 1000;

    /**
     * @notice Initiate a deposit of assets into the vault.
     * @dev This function is payable, and the amount of ETH sent is used to pay for low-latency price validation.
     * @param amount The amount of wstETH to deposit.
     * @param currentPriceData The latest price data
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function initiateDeposit(uint128 amount, bytes calldata currentPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        uint40 timestamp = uint40(block.timestamp);

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            timestamp, ProtocolAction.InitiateDeposit, currentPriceData
        );

        bool priceUpdated =
            _applyPnlAndFunding(currentPrice.neutralPrice.toUint128(), currentPrice.timestamp.toUint128());
        // liquidate if pnl applied
        if (priceUpdated) {
            _liquidatePositions(currentPrice.price, _liquidationIteration);
        }

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateDeposit,
            timestamp: timestamp,
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: amount,
            assetPrice: _lastPrice, // we use `_lastPrice` because it might be more recent than `currentPrice.price`
            totalExpoOrTickVersion: _totalExpo,
            balanceVault: _balanceVault,
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        _addPendingAction(msg.sender, pendingAction);

        _retrieveAssetsAndCheckBalance(msg.sender, amount);

        emit InitiatedDeposit(msg.sender, amount);
        _executePendingAction(previousActionPriceData);
    }

    function validateDeposit(bytes calldata depositPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateDeposit(msg.sender, depositPriceData);
        _executePendingAction(previousActionPriceData);
    }

    function initiateWithdrawal(
        uint128 usdnAmount,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable initializedAndNonReentrant {
        if (usdnAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        uint40 timestamp = uint40(block.timestamp);

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            timestamp, ProtocolAction.InitiateWithdrawal, currentPriceData
        );

        bool priceUpdated =
            _applyPnlAndFunding(currentPrice.neutralPrice.toUint128(), currentPrice.timestamp.toUint128());
        // liquidate if pnl applied
        if (priceUpdated) {
            _liquidatePositions(currentPrice.price, _liquidationIteration);
        }

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateWithdrawal,
            timestamp: timestamp,
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: usdnAmount,
            assetPrice: _lastPrice, // we use `_lastPrice` because it might be more recent than `currentPrice.price`
            totalExpoOrTickVersion: _totalExpo,
            balanceVault: _balanceVault,
            balanceLong: _balanceLong,
            usdnTotalSupply: _usdn.totalSupply()
        });

        _addPendingAction(msg.sender, pendingAction);

        // retrieve the USDN tokens, checks that balance is sufficient
        _usdn.safeTransferFrom(msg.sender, address(this), usdnAmount);

        emit InitiatedWithdrawal(msg.sender, usdnAmount);
        _executePendingAction(previousActionPriceData);
    }

    function validateWithdrawal(bytes calldata withdrawalPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateWithdrawal(msg.sender, withdrawalPriceData);
        _executePendingAction(previousActionPriceData);
    }

    function initiateOpenPosition(
        uint96 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable initializedAndNonReentrant returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        uint40 timestamp = uint40(block.timestamp);

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            timestamp, ProtocolAction.InitiateOpenPosition, currentPriceData
        );

        {
            bool priceUpdated =
                _applyPnlAndFunding(currentPrice.neutralPrice.toUint128(), currentPrice.timestamp.toUint128());
            // liquidate if pnl applied
            if (priceUpdated) {
                _liquidatePositions(currentPrice.price, _liquidationIteration);
            }
        }

        uint128 leverage;
        {
            // we calculate the closest valid tick down for the desired liq price without liquidation penalty
            int24 desiredLiqTick = getEffectiveTickForPrice(desiredLiqPrice);
            uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(desiredLiqTick);

            // calculate position leverage
            // reverts if liquidationPrice >= entryPrice
            leverage = _getLeverage(currentPrice.price.toUint128(), liqPriceWithoutPenalty);
            if (leverage < _minLeverage) {
                revert UsdnProtocolLeverageTooLow();
            }
            if (leverage > _maxLeverage) {
                revert UsdnProtocolLeverageTooHigh();
            }

            // Apply liquidation penalty
            tick_ = desiredLiqTick + int24(_liquidationPenalty) * _tickSpacing;
        }

        // Calculate effective liquidation price
        uint128 liquidationPrice = getEffectivePriceForTick(tick_);

        // Liquidation price must be at least x% below current price
        _checkSafetyMargin(currentPrice.price.toUint128(), liquidationPrice);

        // Register position and adjust contract state
        {
            Position memory long = Position({
                user: msg.sender,
                amount: amount,
                startPrice: currentPrice.price.toUint128(),
                leverage: leverage,
                timestamp: timestamp
            });
            (tickVersion_, index_) = _saveNewPosition(tick_, long);

            // Register pending action
            PendingAction memory pendingAction = PendingAction({
                action: ProtocolAction.InitiateOpenPosition,
                timestamp: timestamp,
                user: msg.sender,
                tick: tick_,
                amountOrIndex: index_.toUint128(),
                assetPrice: 0,
                totalExpoOrTickVersion: tickVersion_,
                balanceVault: 0,
                balanceLong: 0,
                usdnTotalSupply: 0
            });
            _addPendingAction(msg.sender, pendingAction);
            emit InitiatedOpenPosition(msg.sender, long, tick_, tickVersion_, index_);
        }
        _retrieveAssetsAndCheckBalance(msg.sender, amount);

        _executePendingAction(previousActionPriceData);
    }

    function validateOpenPosition(bytes calldata openPriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateOpenPosition(msg.sender, openPriceData);
        _executePendingAction(previousActionPriceData);
    }

    function initiateClosePosition(
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable initializedAndNonReentrant {
        // check if the position belongs to the user
        Position memory pos = getLongPosition(tick, tickVersion, index);
        if (pos.user != msg.sender) {
            revert UsdnProtocolUnauthorized();
        }

        uint40 timestamp = uint40(block.timestamp);
        {
            PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
                timestamp, ProtocolAction.InitiateClosePosition, currentPriceData
            );

            bool priceUpdated =
                _applyPnlAndFunding(currentPrice.neutralPrice.toUint128(), currentPrice.timestamp.toUint128());
            // liquidate if pnl applied
            if (priceUpdated) {
                _liquidatePositions(currentPrice.price, _liquidationIteration);
            }
        }

        {
            (, uint256 version) = _tickHash(tick);
            if (version != tickVersion) {
                // our position was liquidated
                // can't close a liquidated position
                // TODO: emit event
                return;
            }
        }

        uint256 liqMultiplier = _liquidationMultiplier;
        uint256 tempTransfer = _assetToTransfer(tick, pos.amount, pos.leverage, liqMultiplier);

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateClosePosition,
            timestamp: timestamp,
            user: msg.sender,
            tick: tick,
            amountOrIndex: pos.amount, // TODO: rename to `amount` and use `usdnTotalSupplyOrPosIndex` for
                // deposit/withdraw
            assetPrice: pos.leverage, // TODO: rename struct field to `assetPriceOrLeverage`
            totalExpoOrTickVersion: tickVersion,
            balanceVault: liqMultiplier, // TODO: rename struct field to `balanceVaultOrLiqMultiplier`
            balanceLong: tempTransfer, // TODO: rename struct field to `balanceLongOrTempTransfer`
            usdnTotalSupply: index // TODO: rename struct field to `usdnTotalSupplyOrPosIndex`
         });

        // decrease balance optimistically (exact amount will be recalculated during validation)
        // transfer will be done after validation
        _balanceLong -= tempTransfer;

        _addPendingAction(msg.sender, pendingAction);

        _removePosition(tick, tickVersion, index, pos);

        emit InitiatedClosePosition(msg.sender, tick, tickVersion, index);
        _executePendingAction(previousActionPriceData);
    }

    function validateClosePosition(bytes calldata closePriceData, bytes calldata previousActionPriceData)
        external
        payable
        initializedAndNonReentrant
    {
        _validateClosePosition(msg.sender, closePriceData);
        _executePendingAction(previousActionPriceData);
    }

    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidated_)
    {
        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint40(block.timestamp), ProtocolAction.Liquidation, currentPriceData
        );

        _applyPnlAndFunding(currentPrice.neutralPrice.toUint128(), currentPrice.timestamp.toUint128());

        liquidated_ = _liquidatePositions(currentPrice.price, iterations);

        // TODO: add liquidator incentive if needed
    }

    function _validateDeposit(address user, bytes calldata priceData) internal {
        PendingAction memory deposit = _getPendingAction(user, true); // clear pending action

        // check type of action
        if (deposit.action != ProtocolAction.InitiateDeposit) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (deposit.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateDepositWithAction(deposit, priceData, false);
    }

    function _validateDepositWithAction(PendingAction memory deposit, bytes calldata priceData, bool initializing)
        internal
        returns (PriceInfo memory depositPrice_)
    {
        // During initialization, we might want to use a different oracle, so we have a special action
        ProtocolAction action = initializing ? ProtocolAction.Initialize : ProtocolAction.ValidateDeposit;

        depositPrice_ =
            _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(deposit.timestamp, action, priceData);

        // adjust balances
        if (!initializing) {
            // There is no need to adjust balances during initialization.
            // Also, during initialization, `_lastUpdateTimestamp` and `_lastPrice` are not updated yet.
            _applyPnlAndFunding(depositPrice_.neutralPrice.toUint128(), depositPrice_.timestamp.toUint128());
        }

        // We calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint.

        // During initialization, the deposit.assetPrice is zero, so we use the price provided for validation.
        uint256 oldPrice = initializing ? depositPrice_.price : deposit.assetPrice;

        // The last parameter (price) is only used during initialization
        uint256 usdnToMint1 =
            _calcMintUsdn(deposit.amountOrIndex, deposit.balanceVault, deposit.usdnTotalSupply, oldPrice);
        uint256 usdnToMint2 = _calcMintUsdn(
            deposit.amountOrIndex,
            uint256(
                _vaultAssetAvailable(
                    deposit.totalExpoOrTickVersion,
                    deposit.balanceVault,
                    deposit.balanceLong,
                    depositPrice_.price.toUint128(), // new price
                    deposit.assetPrice // old price
                )
            ),
            deposit.usdnTotalSupply,
            depositPrice_.price
        );
        uint256 usdnToMint;
        if (usdnToMint1 <= usdnToMint2) {
            usdnToMint = usdnToMint1;
        } else {
            usdnToMint = usdnToMint2;
        }

        _balanceVault += deposit.amountOrIndex;

        if (initializing) {
            // we mint the minimum amount of USDN to the dead address, so that the total supply never falls to zero
            _usdn.mint(DEAD_ADDRESS, MIN_USDN_SUPPLY);
            uint256 mintToUser = usdnToMint - MIN_USDN_SUPPLY;
            _usdn.mint(deposit.user, mintToUser);
            emit ValidatedDeposit(DEAD_ADDRESS, 0, MIN_USDN_SUPPLY);
            emit ValidatedDeposit(deposit.user, deposit.amountOrIndex, mintToUser);
        } else {
            _usdn.mint(deposit.user, usdnToMint);
            emit ValidatedDeposit(deposit.user, deposit.amountOrIndex, usdnToMint);
        }
    }

    function _validateWithdrawal(address user, bytes calldata priceData) internal {
        PendingAction memory withdrawal = _getPendingAction(user, true); // clear pending action

        // check type of action
        if (withdrawal.action != ProtocolAction.InitiateWithdrawal) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (withdrawal.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateWithdrawalWithAction(withdrawal, priceData);
    }

    function _validateWithdrawalWithAction(PendingAction memory withdrawal, bytes calldata priceData) internal {
        PriceInfo memory withdrawalPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            withdrawal.timestamp, ProtocolAction.ValidateWithdrawal, priceData
        );

        // adjust balances
        _applyPnlAndFunding(withdrawalPrice.neutralPrice.toUint128(), withdrawalPrice.timestamp.toUint128());

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.

        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = uint256(
            _vaultAssetAvailable(
                withdrawal.totalExpoOrTickVersion,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                withdrawalPrice.price.toUint128(), // new price
                withdrawal.assetPrice // old price
            )
        );
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 assetToTransfer =
            FixedPointMathLib.fullMulDiv(withdrawal.amountOrIndex, available, withdrawal.usdnTotalSupply);

        _balanceVault -= assetToTransfer;
        // we have the USDN in the contract already
        _usdn.burn(withdrawal.amountOrIndex);

        // send the asset to the user
        _distributeAssetsAndCheckBalance(withdrawal.user, assetToTransfer);

        emit ValidatedWithdrawal(withdrawal.user, assetToTransfer, withdrawal.amountOrIndex);
    }

    function _validateOpenPosition(address user, bytes calldata priceData) internal {
        PendingAction memory open = _getPendingAction(user, true); // clear pending action

        // check type of action
        if (open.action != ProtocolAction.InitiateOpenPosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (open.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateOpenPositionWithAction(open, priceData);
    }

    function _validateOpenPositionWithAction(PendingAction memory long, bytes calldata priceData) internal {
        int24 tick = long.tick;
        uint256 tickVersion = long.totalExpoOrTickVersion;
        uint256 index = long.amountOrIndex;

        (bytes32 tickHash, uint256 version) = _tickHash(tick);

        if (version != tickVersion) {
            // The current tick version doesn't match the version from the pending action.
            // This means the position has been liquidated in the mean time
            // TODO: emit event notifying the user
            return;
        }

        PriceInfo memory price = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            long.timestamp, ProtocolAction.ValidateOpenPosition, priceData
        );

        // adjust balances
        _applyPnlAndFunding(price.neutralPrice.toUint128(), price.timestamp.toUint128());

        // TODO: if price <= liquidationPrice, re-calculate a liquidation price based on the leverage so that the
        // position remains solvent. Emit LiquidationPriceChanged.

        // Re-calculate leverage
        uint128 liqPriceWithoutPenalty = getEffectivePriceForTick(tick - int24(_liquidationPenalty) * _tickSpacing);
        // reverts if liquidationPrice >= entryPrice
        uint128 leverage = _getLeverage(price.price.toUint128(), liqPriceWithoutPenalty);
        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        if (leverage > _maxLeverage) {
            // TODO: We should adjust liquidation price to have a leverage of _maxLeverage
            // Update the `tick` and `index` variables.
            // Emit LiquidationPriceChanged.
        }

        // Adjust position parameters
        Position storage pos = _longPositions[tickHash][index];
        pos.leverage = leverage;
        pos.startPrice = price.price.toUint128();

        emit ValidatedOpenPosition(long.user, pos, tick, tickVersion, index, getEffectivePriceForTick(tick));
    }

    function _validateClosePosition(address user, bytes calldata priceData) internal {
        PendingAction memory close = _getPendingAction(user, true); // clear pending action

        // check type of action
        if (close.action != ProtocolAction.InitiateClosePosition) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (close.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateClosePositionWithAction(close, priceData);
    }

    function _validateClosePositionWithAction(PendingAction memory long, bytes calldata priceData) internal {
        int24 tick = long.tick;
        uint256 amount = long.amountOrIndex;
        uint128 leverage = long.assetPrice;
        uint256 liqMultiplier = long.balanceVault;
        uint256 tempTransfer = long.balanceLong;

        // TODO: how to check if position was liquidated during the 24s between initiate and validate?

        PriceInfo memory price = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            long.timestamp, ProtocolAction.ValidateClosePosition, priceData
        );

        // adjust balances
        _applyPnlAndFunding(price.neutralPrice.toUint128(), price.timestamp.toUint128());

        uint256 assetToTransfer = _assetToTransfer(tick, amount, leverage, liqMultiplier);

        // adjust long balance that was previously optimistically decreased
        if (assetToTransfer > tempTransfer) {
            // we didn't remove enough
            _balanceLong -= assetToTransfer - tempTransfer;
        } else if (assetToTransfer < tempTransfer) {
            // we removed too much
            _balanceLong += tempTransfer - assetToTransfer;
        }

        // send the asset to the user
        _distributeAssetsAndCheckBalance(long.user, assetToTransfer);

        emit ValidatedClosePosition(
            long.user,
            tick,
            long.totalExpoOrTickVersion, // tick version
            long.usdnTotalSupply, // index
            assetToTransfer,
            int256(assetToTransfer) - amount.toInt256()
        );
    }

    function _assetToTransfer(int24 tick, uint256 posAmount, uint128 posLeverage, uint256 liqMultiplier)
        internal
        view
        returns (uint256 assetToTransfer_)
    {
        uint128 lastPrice = _lastPrice;
        // calculate amount to transfer
        int256 available = _longAssetAvailable(lastPrice);
        if (available < 0) {
            available = 0;
        }

        // Calculate position value
        int256 value = positionValue(
            lastPrice,
            _getEffectivePriceForTick(tick - int24(_liquidationPenalty) * _tickSpacing, liqMultiplier),
            posAmount,
            posLeverage
        ).toInt256();

        if (value > available) {
            assetToTransfer_ = uint256(available);
        } else {
            assetToTransfer_ = uint256(value);
        }
    }

    function _executePendingAction(bytes calldata priceData) internal {
        PendingAction memory pending = _getActionablePendingAction(0); // use default maxIter
        if (pending.action == ProtocolAction.None) {
            // no pending action
            return;
        } else if (pending.action == ProtocolAction.InitiateDeposit) {
            _validateDepositWithAction(pending, priceData, false);
        } else if (pending.action == ProtocolAction.InitiateWithdrawal) {
            _validateWithdrawalWithAction(pending, priceData);
        } else if (pending.action == ProtocolAction.InitiateOpenPosition) {
            _validateOpenPositionWithAction(pending, priceData);
        } else if (pending.action == ProtocolAction.InitiateClosePosition) {
            _validateClosePositionWithAction(pending, priceData);
        }
    }
}
