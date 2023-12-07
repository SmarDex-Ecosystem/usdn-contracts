// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { DoubleEndedQueue } from "src/libraries/Deque.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    function initiateDeposit(uint128 _amount, bytes calldata _previousActionPriceData) external payable {
        if (_amount == 0) revert UsdnProtocolZeroAmount();
        if (pendingVaultActions[msg.sender] > 0) revert UsdnProtocolPendingAction();

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

        uint128 _rawIndex = pendingActionsQueue.pushBack(_pendingAction);
        pendingVaultActions[msg.sender] = uint256(_rawIndex) + 1; // shift by one so that zero means no pending action

        _retrieveAssetsAndCheckBalance(msg.sender, _amount);
    }

    function validateDeposit(bytes calldata _depositPriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        uint256 _pendingActionIndex = pendingVaultActions[msg.sender];
        if (_pendingActionIndex == 0) revert UsdnProtocolNoPendingAction();

        uint128 _rawIndex = uint128(_pendingActionIndex - 1);
        PendingAction memory _deposit = pendingActionsQueue.atRaw(_rawIndex);

        // sanity check
        if (_deposit.action != ProtocolAction.InitiateDeposit) revert UsdnProtocolInvalidPendingAction();

        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        PriceInfo memory _depositPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            _deposit.timestamp, ProtocolAction.ValidateDeposit, _depositPriceData
        );

        _validateDeposit(msg.sender, _deposit.amount, _depositPrice.price, _depositPrice.timestamp, _rawIndex);
    }

    function _validateDeposit(
        address _user,
        uint128 _amount,
        uint128 _depositPrice,
        uint128 _depositTimestamp,
        uint128 _queueIndex
    ) internal {
        // remove the pending action
        pendingActionsQueue.clearAt(_queueIndex);
        delete pendingVaultActions[_user];
        // TODO: if the queue index is equal to the front of the queue, we need to pop it so that the front pointer
        // gets updated. maybe do it in clearAt directly?

        // adjust balances
        _applyPnlAndFunding(_depositPrice, _depositTimestamp);

        uint256 _usdnToMint = _calcMintUsdn(_amount, _depositPrice);
        usdn.mint(msg.sender, _usdnToMint);

        balanceVault += _amount;
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
