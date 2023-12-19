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
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function initiateDeposit(uint128 amount, bytes calldata previousActionPriceData) external payable {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        _executePendingAction(previousActionPriceData);

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

    function initiateWithdrawal(uint128 usdnAmount, bytes calldata previousActionPriceData) external payable {
        if (usdnAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        _executePendingAction(previousActionPriceData);

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
    }

    function validateWithdrawal(bytes calldata withdrawalPriceData, bytes calldata previousActionPriceData)
        external
        payable
    {
        _executePendingAction(previousActionPriceData);

        _validateWithdrawal(msg.sender, withdrawalPriceData);
    }

    function initiateOpenLong(
        uint96 amount,
        uint128 liquidationPrice,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable returns (int24 tick_, uint256 index_) {
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        _executePendingAction(previousActionPriceData);

        uint40 timestamp = uint40(block.timestamp);
        // find tick corresponding to the liquidation price (rounds down)
        tick_ = _getTickForPrice(liquidationPrice);
        // calculate effective liquidation price once we have the tick (lower than or equal to the desired liq price)
        liquidationPrice = _getPriceForTick(tick_);

        PriceInfo memory currentPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            timestamp, ProtocolAction.InitiateOpenPosition, currentPriceData
        );

        // Apply liquidation penalty
        uint128 entryPrice =
            uint128(currentPrice.price * (PERCENTAGE_DIVISOR + _liquidationPenalty) / PERCENTAGE_DIVISOR);

        uint40 leverage = getLeverage(entryPrice, liquidationPrice); // reverts if liquidationPrice >= entryPrice
        if (leverage < _minLeverage) {
            revert UsdnProtocolLeverageTooLow();
        }
        if (leverage > _maxLeverage) {
            revert UsdnProtocolLeverageTooHigh();
        }

        // Safety margin (liquidation price must be at least x% below entry price)
        {
            uint128 maxLiquidationPrice =
                uint128(currentPrice.price * (PERCENTAGE_DIVISOR - _safetyMargin) / PERCENTAGE_DIVISOR);
            if (liquidationPrice < maxLiquidationPrice) {
                revert UsdnProtocolLiquidationPriceSafetyMargin(liquidationPrice, maxLiquidationPrice);
            }
        }

        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);

        // Adjust state
        _balanceLong += amount;
        bytes32 tickHash = _tickHash(tick_);
        {
            uint256 addExpo = (amount * leverage) / 10 ** LEVERAGE_DECIMALS;
            _totalExpo += addExpo;
            _totalExpoByTick[tickHash] += addExpo;
        }
        _totalLongPositions += 1;

        // Register position
        {
            Position memory long = Position({
                user: msg.sender,
                amount: amount,
                startPrice: entryPrice,
                leverage: leverage,
                validated: false,
                isExit: false,
                timestamp: timestamp
            });
            Position[] storage pos = _longPositions[tickHash];
            if (_positionsInTick[tickHash] == 0) {
                // first position in this tick
                _tickBitmap.set(_tickToBitmapIndex(tick_));
            }
            if (tick_ > _maxInitializedTick) {
                // keep track of max initialized tick
                _maxInitializedTick = tick_;
            }
            pos.push(long);
            ++_positionsInTick[tickHash];
            index_ = pos.length - 1;
        }

        // Register pending action
        {
            PendingAction memory pendingAction = PendingAction({
                action: ProtocolAction.InitiateOpenPosition,
                timestamp: timestamp,
                user: msg.sender,
                tick: tick_,
                amountOrIndex: amount
            });

            _addPendingAction(msg.sender, pendingAction);
        }

        _retrieveAssetsAndCheckBalance(msg.sender, amount);

        emit InitiatedOpenLong(msg.sender, amount);
    }

    function validateOpenPosition(bytes calldata openPriceData, bytes calldata previousActionPriceData)
        external
        payable
    {
        _executePendingAction(previousActionPriceData);

        _validateOpenPosition(msg.sender, openPriceData);
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

    function _validateOpenPositionWithAction(PendingAction memory open, bytes calldata priceData) internal {
        // TODO
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
            // TODO
        }
    }
}
