// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract MockOracleMiddleware is IOracleMiddleware {
    uint8 internal constant DECIMALS = 18;
    uint256 internal _validationDelay = 24 seconds;
    // if true, then the middleware requires a payment of 1 wei for any action
    bool internal _requireValidationCost = false;

    /// @inheritdoc IOracleMiddleware
    function parseAndValidatePrice(uint128 targetTimestamp, ProtocolAction action, bytes calldata data)
        external
        payable
        returns (PriceInfo memory)
    {
        uint128 priceValue = abi.decode(data, (uint128));
        uint128 ts = targetTimestamp;
        if (
            action == ProtocolAction.InitiateDeposit || action == ProtocolAction.InitiateWithdrawal
                || action == ProtocolAction.InitiateOpenPosition || action == ProtocolAction.InitiateClosePosition
                || action == ProtocolAction.Initialize
        ) {
            if (ts < 30 minutes) {
                // avoid underflow
                ts = 0;
            } else {
                ts -= 30 minutes; // simulate that we got the price 30 minutes ago
            }
        } else if (action == ProtocolAction.Liquidation) {
            if (ts < 30 seconds) {
                // avoid underflow
                ts = 0;
            } else {
                ts -= 30 seconds; // for liquidation, simulate we got a recent timestamp
            }
        } else {
            // for other actions, simulate we got the price from 24s after the initiate action
            ts += uint128(_validationDelay);
        }

        PriceInfo memory price = PriceInfo({ price: priceValue, neutralPrice: priceValue, timestamp: uint48(ts) });
        return price;
    }

    /// @inheritdoc IOracleMiddleware
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IOracleMiddleware
    function validationDelay() external view returns (uint256) {
        return _validationDelay;
    }

    /// @inheritdoc IOracleMiddleware
    function validationCost(bytes calldata, ProtocolAction) external view returns (uint256) {
        return _requireValidationCost ? 1 : 0;
    }

    function updateValidationDelay(uint256 newDelay) external {
        _validationDelay = newDelay;
    }

    function requireValidationCost() external view returns (bool) {
        return _requireValidationCost;
    }

    function setRequireValidationCost(bool req) external {
        _requireValidationCost = req;
    }
}
