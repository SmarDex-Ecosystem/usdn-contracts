// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Position, ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";
import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    function initiateDeposit(uint128 _amount, bytes calldata _previousActionPriceData) external payable {
        if (_amount == 0) revert UsdnProtocolZeroAmount();
        if (pendingVaultActions[msg.sender].amount > 0) revert UsdnProtocolPendingAction();

        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        uint40 _timestamp = uint40(block.timestamp);

        Position memory _tempDeposit = Position({
            user: msg.sender,
            amount: _amount,
            startPrice: 0,
            leverage: 0,
            validated: false,
            isExit: false,
            timestamp: _timestamp
        });

        pendingVaultActions[msg.sender] = _tempDeposit;

        PendingAction memory _pendingAction =
            PendingAction({ action: ProtocolAction.InitiateDeposit, user: msg.sender, timestamp: _timestamp });

        pendingActions.push(_pendingAction);

        _transferFromAndCheckBalance(msg.sender, _amount);
    }

    function validateDeposit(bytes calldata _depositPriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        Position memory _deposit = pendingVaultActions[msg.sender];
        if (_deposit.amount == 0) revert UsdnProtocolNoPendingAction();

        // TODO: validate previous action if needed, using the provided price update
        _previousActionPriceData;

        PriceInfo memory _depositPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            _deposit.timestamp, ProtocolAction.ValidateDeposit, _depositPriceData
        );

        delete pendingVaultActions[msg.sender]; // remove the pending action
        pendingActionsHead++; // mark the action as validated

        // adjust balances
        _applyPnlAndFunding(_depositPrice.price, _depositPrice.timestamp);

        uint256 _usdnToMint = _calcMintUsdn(_deposit.amount, _depositPrice.price);
        usdn.mint(msg.sender, _usdnToMint);

        balanceVault += _deposit.amount;
    }

    function _calcMintUsdn(uint256 _amount, uint128 _currentPrice) internal view returns (uint256 toMint_) {
        toMint_ = (_amount * _currentPrice) / 10 ** (assetDecimals + priceFeedDecimals - usdn.decimals());
    }
}
