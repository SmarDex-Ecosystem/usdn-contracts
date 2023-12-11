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

    uint256 constant MIN_USDN_SUPPLY = 1000;

    function initiateDeposit(uint128 _amount, bytes calldata _previousActionPriceData) external payable {
        if (_amount == 0) revert UsdnProtocolZeroAmount();

        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        uint40 _timestamp = uint40(block.timestamp);

        PendingAction memory _pendingAction = PendingAction({
            action: ProtocolAction.InitiateDeposit,
            timestamp: _timestamp,
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: _amount
        });

        _addPendingAction(msg.sender, _pendingAction);

        _retrieveAssetsAndCheckBalance(msg.sender, _amount);

        emit InitiatedDeposit(msg.sender, _amount);
    }

    function validateDeposit(bytes calldata _depositPriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        _validateDeposit(msg.sender, _depositPriceData);
    }

    function initiateWithdrawal(uint128 _usdnAmount, bytes calldata _previousActionPriceData) external payable {
        if (_usdnAmount == 0) revert UsdnProtocolZeroAmount();

        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        uint40 _timestamp = uint40(block.timestamp);

        PendingAction memory _pendingAction = PendingAction({
            action: ProtocolAction.InitiateWithdrawal,
            timestamp: _timestamp,
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: _usdnAmount
        });

        _addPendingAction(msg.sender, _pendingAction);

        // retrieve the USDN tokens, checks that balance is sufficient
        usdn.safeTransferFrom(msg.sender, address(this), _usdnAmount);

        emit InitiatedWithdrawal(msg.sender, _usdnAmount);
    }

    function _validateDeposit(address _user, bytes calldata _priceData) internal {
        PendingAction memory _deposit = _getAndClearPendingAction(_user);

        // check type of action
        if (_deposit.action != ProtocolAction.InitiateDeposit) revert UsdnProtocolInvalidPendingAction();

        PriceInfo memory _depositPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            _deposit.timestamp, ProtocolAction.ValidateDeposit, _priceData
        );

        // adjust balances
        _applyPnlAndFunding(_depositPrice.price, _depositPrice.timestamp);

        uint256 _usdnToMint = _calcMintUsdn(_deposit.amountOrIndex, _depositPrice.price);
        usdn.mint(_user, _usdnToMint);

        balanceVault += _deposit.amountOrIndex;

        emit ValidatedDeposit(_user, _deposit.amountOrIndex, _usdnToMint);
    }

    function _validateWithdrawal(address _user, bytes calldata _priceData) internal {
        PendingAction memory _withdrawal = _getAndClearPendingAction(_user);

        // check type of action
        if (_withdrawal.action != ProtocolAction.InitiateWithdrawal) revert UsdnProtocolInvalidPendingAction();

        // check supply
        uint256 _totalSupply = usdn.totalSupply();
        if (_totalSupply - _withdrawal.amountOrIndex < 1000) {
            revert UsdnProtocolMinTotalSupply(); // totalSupply cannot fall too low
        }

        PriceInfo memory _withdrawalPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            _withdrawal.timestamp, ProtocolAction.ValidateWithdrawal, _priceData
        );

        // adjust balances
        _applyPnlAndFunding(_withdrawalPrice.price, _withdrawalPrice.timestamp);

        int256 _available = vaultAssetAvailable(_withdrawalPrice.price);
        if (_available < 0) {
            _available = 0; // clamp to zero
        }
        // _assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 _assetToTransfer = (_withdrawal.amountOrIndex * uint256(_available)) / _totalSupply;
        balanceVault -= _assetToTransfer;
        // we have the USDN in the contract already
        usdn.burn(_withdrawal.amountOrIndex);

        // send the asset to the user
        _distributeAssetsAndCheckBalance(_user, _assetToTransfer);

        emit ValidatedWithdrawal(_user, _assetToTransfer, _withdrawal.amountOrIndex);
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset according to its current price.
     * @param _amount The amount of asset that were deposited.
     * @param _currentPrice The current price of the asset.
     */
    function _calcMintUsdn(uint256 _amount, uint128 _currentPrice) internal view returns (uint256 toMint_) {
        toMint_ = FixedPointMathLib.fullMulDiv(
            _amount, _currentPrice, 10 ** (assetDecimals + priceFeedDecimals - usdnDecimals)
        );
    }
}
