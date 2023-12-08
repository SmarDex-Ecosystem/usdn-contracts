// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    function initiateDeposit(uint128 _amount, bytes calldata _previousActionPriceData) external payable {
        if (_amount == 0) revert UsdnProtocolZeroAmount();

        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        uint40 _timestamp = uint40(block.timestamp);

        PendingAction memory _pendingAction = PendingAction({
            action: ProtocolAction.InitiateDeposit,
            timestamp: _timestamp,
            user: msg.sender,
            tick: 0,
            amount: _amount,
            index: 0
        });

        _addPendingAction(msg.sender, _pendingAction);

        _retrieveAssetsAndCheckBalance(msg.sender, _amount);
    }

    function validateDeposit(bytes calldata _depositPriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        _validateDeposit(msg.sender, _depositPriceData);
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

        uint256 _usdnToMint = _calcMintUsdn(_deposit.amount, _depositPrice.price);
        usdn.mint(_user, _usdnToMint);

        balanceVault += _deposit.amount;
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
