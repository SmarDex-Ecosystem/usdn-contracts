// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
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

        // TODO: validate previous action if needed, using the provided price update
        previousActionPriceData;

        uint40 timestamp = uint40(block.timestamp);

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateDeposit,
            timestamp: timestamp,
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
        // TODO: validate previous action if needed, using the provided price update
        previousActionPriceData;

        _validateDeposit(msg.sender, depositPriceData);
    }

    function initiateWithdrawal(uint128 usdnAmount, bytes calldata previousActionPriceData) external payable {
        if (usdnAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        // TODO: validate previous action if needed, using the provided price update
        previousActionPriceData;

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
        // TODO: validate previous action if needed, using the provided price update
        previousActionPriceData;

        _validateWithdrawal(msg.sender, withdrawalPriceData);
    }

    function _validateDeposit(address user, bytes calldata priceData) internal {
        PendingAction memory deposit = _getAndClearPendingAction(user);

        // check type of action
        if (deposit.action != ProtocolAction.InitiateDeposit) {
            revert UsdnProtocolInvalidPendingAction();
        }

        PriceInfo memory depositPrice = _oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            deposit.timestamp, ProtocolAction.ValidateDeposit, priceData
        );

        // adjust balances
        _applyPnlAndFunding(depositPrice.price, depositPrice.timestamp);

        uint256 usdnToMint = _calcMintUsdn(deposit.amountOrIndex, depositPrice.price);
        _usdn.mint(user, usdnToMint);

        _balanceVault += deposit.amountOrIndex;

        emit ValidatedDeposit(user, deposit.amountOrIndex, usdnToMint);
    }

    function _validateWithdrawal(address user, bytes calldata priceData) internal {
        PendingAction memory withdrawal = _getAndClearPendingAction(user);

        // check type of action
        if (withdrawal.action != ProtocolAction.InitiateWithdrawal) {
            revert UsdnProtocolInvalidPendingAction();
        }

        // check supply
        uint256 totalSupply = _usdn.totalSupply();
        if (totalSupply - withdrawal.amountOrIndex < 1000) {
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
        _distributeAssetsAndCheckBalance(user, assetToTransfer);

        emit ValidatedWithdrawal(user, assetToTransfer, withdrawal.amountOrIndex);
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset according to its current price.
     * @param amount The amount of asset that were deposited.
     * @param currentPrice The current price of the asset.
     */
    function _calcMintUsdn(uint256 amount, uint128 currentPrice) internal view returns (uint256 toMint_) {
        toMint_ = FixedPointMathLib.fullMulDiv(
            amount, currentPrice, 10 ** (_assetDecimals + _priceFeedDecimals - _usdnDecimals)
        );
    }
}
