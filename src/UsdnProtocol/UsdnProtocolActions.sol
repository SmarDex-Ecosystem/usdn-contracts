// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";

abstract contract UsdnProtocolActions is UsdnProtocolLong {
    using SafeERC20 for IUsdn;

    /**
     * @dev The minimum total supply of USDN that we allow.
     * This should never be a problem, because the first deposit's USDN (on initialize) is sent to the dead address and
     * cannot be recovered.
     */
    uint256 constant MIN_USDN_SUPPLY = 1000;

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

        uint40 timestamp = uint40(block.timestamp);

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateWithdrawal,
            timestamp: timestamp,
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

        uint256 usdnToMint = _calcMintUsdn(deposit.amountOrIndex, depositPrice.price);
        _usdn.mint(deposit.user, usdnToMint);

        _balanceVault += deposit.amountOrIndex;

        emit ValidatedDeposit(deposit.user, deposit.amountOrIndex, usdnToMint);
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
        // check supply
        uint256 totalSupply = _usdn.totalSupply();
        if (totalSupply - withdrawal.amountOrIndex < MIN_USDN_SUPPLY) {
            revert UsdnProtocolMinTotalSupply(); // totalSupply cannot fall too low
        }

        PriceInfo memory withdrawalPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            withdrawal.timestamp, ProtocolAction.ValidateWithdrawal, priceData
        );

        // adjust balances
        _applyPnlAndFunding(withdrawalPrice.price, withdrawalPrice.timestamp);

        int256 available = vaultAssetAvailable(withdrawalPrice.price);
        if (available < 0) {
            available = 0; // clamp to zero
        }
        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 assetToTransfer = (withdrawal.amountOrIndex * uint256(available)) / totalSupply;
        _balanceVault -= assetToTransfer;
        // we have the USDN in the contract already
        _usdn.burn(withdrawal.amountOrIndex);

        // send the asset to the user
        _distributeAssetsAndCheckBalance(withdrawal.user, assetToTransfer);

        emit ValidatedWithdrawal(withdrawal.user, assetToTransfer, withdrawal.amountOrIndex);
    }

    function _executePendingAction(bytes calldata priceData) internal {
        PendingAction memory pending = getActionablePendingAction();
        if (pending.action == ProtocolAction.None) {
            // no pending action
            return;
        } else if (pending.action == ProtocolAction.InitiateDeposit) {
            _validateDepositWithAction(pending, priceData, false);
        } else if (pending.action == ProtocolAction.InitiateWithdrawal) {
            _validateWithdrawalWithAction(pending, priceData);
        } else if (pending.action == ProtocolAction.InitiateOpenPosition) {
            // TODO
        } else if (pending.action == ProtocolAction.InitiateClosePosition) {
            // TODO
        }
    }
}
