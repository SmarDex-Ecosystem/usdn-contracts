// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";

abstract contract UsdnProtocolActions is UsdnProtocolLong {
    using SafeERC20 for IUsdn;
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
    {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint40(block.timestamp), ProtocolAction.InitiateDeposit, currentPriceData
        );

        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
        _executePendingAction(previousActionPriceData);
        // TODO: perform liquidation of other pos with currentPrice

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateDeposit,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: amount
        });

        _addPendingAction(msg.sender, pendingAction);

        _retrieveAssetsAndCheckBalance(msg.sender, amount);

        emit InitiatedDeposit(msg.sender, amount);
    }

    function validateDeposit(bytes calldata depositPriceData, bytes calldata previousActionPriceData)
        external
        payable
    {
        _executePendingAction(previousActionPriceData);

        _validateDeposit(msg.sender, depositPriceData);
    }

    function initiateWithdrawal(
        uint128 usdnAmount,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable {
        if (usdnAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint40(block.timestamp), ProtocolAction.InitiateWithdrawal, currentPriceData
        );

        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
        // TODO: perform liquidation of other pos with currentPrice

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateWithdrawal,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: usdnAmount
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
    {
        _executePendingAction(previousActionPriceData);

        _validateWithdrawal(msg.sender, withdrawalPriceData);
    }

    function initiateOpenPosition(
        uint96 amount,
        uint128 liquidationPrice,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable returns (int24 tick_, uint256 index_) {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        // find tick corresponding to the liquidation price (rounds down)
        tick_ = _getEffectiveTickForPrice(liquidationPrice);
        // calculate effective liquidation price once we have the tick (lower than or equal to the desired liq price)
        liquidationPrice = _getEffectivePriceForTick(tick_);

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint40(block.timestamp), ProtocolAction.InitiateOpenPosition, currentPriceData
        );

        // FIXME: use neutral price here!
        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);

        // TODO: perform liquidation of other pos with currentPrice

        // Apply liquidation penalty
        uint128 entryPrice = _entryPriceWithLiquidationPenalty(currentPrice.price);

        uint40 leverage = getLeverage(entryPrice, liquidationPrice); // reverts if liquidationPrice >= entryPrice
        if (leverage < _minLeverage) {
            revert UsdnProtocolLeverageTooLow();
        }
        if (leverage > _maxLeverage) {
            revert UsdnProtocolLeverageTooHigh();
        }

        // Liquidation price must be at least x% below current price
        _checkSafetyMargin(currentPrice.price, liquidationPrice);

        // Register position and adjust contract state
        Position memory long = Position({
            user: msg.sender,
            amount: amount,
            startPrice: entryPrice,
            leverage: leverage,
            timestamp: uint40(block.timestamp)
        });
        index_ = _saveNewPosition(tick_, long);

        // Register pending action
        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateOpenPosition,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            tick: tick_,
            amountOrIndex: index_
        });
        _addPendingAction(msg.sender, pendingAction);

        _retrieveAssetsAndCheckBalance(msg.sender, amount);
        emit InitiatedOpenPosition(msg.sender, long, tick_, index_);
        _executePendingAction(previousActionPriceData);
    }

    function validateOpenPosition(bytes calldata openPriceData, bytes calldata previousActionPriceData)
        external
        payable
    {
        _validateOpenPosition(msg.sender, openPriceData);
        _executePendingAction(previousActionPriceData);
    }

    function initiateClosePosition(
        int24 tick,
        uint256 index,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable {
        // check if the position belongs to the user
        Position memory pos = getLongPosition(tick, index);
        if (pos.user != msg.sender) {
            revert UsdnProtocolUnauthorized();
        }

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint40(block.timestamp), ProtocolAction.InitiateClosePosition, currentPriceData
        );

        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
        // TODO: perform liquidation of other pos with currentPrice

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateClosePosition,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            tick: tick,
            amountOrIndex: index
        });

        _addPendingAction(msg.sender, pendingAction);

        emit InitiatedClosePosition(msg.sender, tick, index);
        _executePendingAction(previousActionPriceData);
    }

    function validateClosePosition(bytes calldata closePriceData, bytes calldata previousActionPriceData)
        external
        payable
    {
        _validateClosePosition(msg.sender, closePriceData);
        _executePendingAction(previousActionPriceData);
    }

    function _validateDeposit(address user, bytes calldata priceData) internal {
        PendingAction memory deposit = _getAndClearPendingAction(user);

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
    {
        // During initialization, we might want to use a different oracle, so we have a special action
        ProtocolAction action = initializing ? ProtocolAction.Initialize : ProtocolAction.ValidateDeposit;

        PriceInfo memory depositPrice =
            _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(deposit.timestamp, action, priceData);

        // adjust balances
        // FIXME: use neutral price here!
        _applyPnlAndFunding(depositPrice.price, depositPrice.timestamp);

        _balanceVault += deposit.amountOrIndex;

        uint256 usdnToMint = _calcMintUsdn(deposit.amountOrIndex, depositPrice.price);
        if (initializing) {
            // we mint the minimum amount of USDN to the dead address, so that the total supply never falls to zero
            _usdn.mint(address(0xdead), MIN_USDN_SUPPLY);
            uint256 mintToUser = usdnToMint - MIN_USDN_SUPPLY;
            _usdn.mint(deposit.user, mintToUser);
            emit ValidatedDeposit(address(0xdead), 0, MIN_USDN_SUPPLY);
            emit ValidatedDeposit(deposit.user, deposit.amountOrIndex, mintToUser);
        } else {
            _usdn.mint(deposit.user, usdnToMint);
            emit ValidatedDeposit(deposit.user, deposit.amountOrIndex, usdnToMint);
        }
    }

    function _validateWithdrawal(address user, bytes calldata priceData) internal {
        PendingAction memory withdrawal = _getAndClearPendingAction(user);

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
        // FIXME: use neutral price here!
        _applyPnlAndFunding(withdrawalPrice.price, withdrawalPrice.timestamp);

        int256 available = _vaultAssetAvailable(withdrawalPrice.price);
        if (available < 0) {
            available = 0; // clamp to zero
        }
        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 assetToTransfer = (withdrawal.amountOrIndex * uint256(available)) / _usdn.totalSupply();
        _balanceVault -= assetToTransfer;
        // we have the USDN in the contract already
        _usdn.burn(withdrawal.amountOrIndex);

        // send the asset to the user
        _distributeAssetsAndCheckBalance(withdrawal.user, assetToTransfer);

        emit ValidatedWithdrawal(withdrawal.user, assetToTransfer, withdrawal.amountOrIndex);
    }

    function _validateOpenPosition(address user, bytes calldata priceData) internal {
        PendingAction memory open = _getAndClearPendingAction(user);

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
        uint256 index = long.amountOrIndex;

        PriceInfo memory price = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            long.timestamp, ProtocolAction.ValidateOpenPosition, priceData
        );

        uint128 liquidationPrice = _getEffectivePriceForTick(tick);

        // adjust balances
        // FIXME: use neutral price here!
        _applyPnlAndFunding(price.price, price.timestamp);

        // TODO: check if can be liquidated according to the provided price
        // If not, then price.price > liquidationPrice

        // Apply liquidation penalty
        uint128 entryPrice = _entryPriceWithLiquidationPenalty(price.price);

        uint40 leverage = getLeverage(entryPrice, liquidationPrice); // reverts if liquidationPrice >= entryPrice
        // Leverage is always greater than 1 (liquidationPrice is positive).
        // Even if it drops below _minLeverage between the initiate and validate actions, we still allow it.
        if (leverage > _maxLeverage) {
            // TODO: We should adjust liquidation price to have a leverage of _maxLeverage
            // Update the `tick`, `index` and `liquidationPrice` variables.
            // Emit LiquidationPriceChanged.
        }

        // Adjust position parameters
        Position storage pos = _longPositions[_tickHash(tick)][index];
        pos.leverage = leverage;
        pos.startPrice = entryPrice;

        emit ValidatedOpenPosition(long.user, pos, tick, index, liquidationPrice);
    }

    function _validateClosePosition(address user, bytes calldata priceData) internal {
        PendingAction memory close = _getAndClearPendingAction(user);

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
        uint256 index = long.amountOrIndex;

        PriceInfo memory price = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            long.timestamp, ProtocolAction.ValidateClosePosition, priceData
        );

        uint128 liquidationPrice = _getEffectivePriceForTick(tick);

        // adjust balances
        // FIXME: use neutral price here!
        _applyPnlAndFunding(price.price, price.timestamp);

        Position memory pos = getLongPosition(tick, index);

        // TODO: check if can be liquidated according to the provided price

        int256 available = _longAssetAvailable(_lastPrice);
        if (available < 0) {
            available = 0;
        }

        int256 value = positionValue(price.price, pos.startPrice, pos.amount, pos.leverage);
        if (value < 0) {
            value = 0;
        }
        uint256 assetToTransfer = uint256(value) > uint256(available) ? uint256(available) : uint256(value);

        // remove the position for the protocol and adjust state
        _balanceLong -= assetToTransfer;
        _removePosition(tick, index, pos);

        // send the asset to the user
        _distributeAssetsAndCheckBalance(pos.user, assetToTransfer);

        emit ValidatedClosePosition(pos.user, tick, index, assetToTransfer, int256(assetToTransfer) - value);
    }

    function _executePendingAction(bytes calldata priceData) internal {
        PendingAction memory pending = getActionablePendingAction(0); // use default maxIter
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
