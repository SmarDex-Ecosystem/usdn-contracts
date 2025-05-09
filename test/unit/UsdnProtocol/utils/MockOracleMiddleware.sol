// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

import { IBaseOracleMiddleware } from "../../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IOracleMiddlewareErrors } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract MockOracleMiddleware is IBaseOracleMiddleware, IOracleMiddlewareErrors, AccessControlDefaultAdminRules {
    uint16 public constant BPS_DIVISOR = 10_000;
    uint16 public constant MAX_CONF_RATIO = BPS_DIVISOR * 2;
    uint8 internal constant DECIMALS = 18;

    uint16 internal _confRatioBps = 4000;
    uint256 internal _validationDelay = 24 seconds;
    uint256 internal _timeElapsedLimit = 1 hours;
    // if true, then the middleware requires a payment of 1 wei for any action
    bool internal _requireValidationCost = false;
    // confidence applied to the price to adjust `PriceInfo.price`
    int256 internal _priceConfBps = 0;

    bytes32 public lastActionId;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() AccessControlDefaultAdminRules(0, msg.sender) {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IBaseOracleMiddleware
    function parseAndValidatePrice(
        bytes32 actionId,
        uint128 targetTimestamp,
        Types.ProtocolAction action,
        bytes calldata data
    ) external payable returns (PriceInfo memory) {
        require(block.timestamp >= 30 minutes, "MockOracleMiddleware: set block timestamp before calling");
        uint256 priceValue = abi.decode(data, (uint128));
        uint256 ts;
        if (
            action == Types.ProtocolAction.InitiateDeposit || action == Types.ProtocolAction.InitiateWithdrawal
                || action == Types.ProtocolAction.InitiateOpenPosition
                || action == Types.ProtocolAction.InitiateClosePosition || action == Types.ProtocolAction.Initialize
        ) {
            // simulate that we got the price 30 minutes ago
            ts = block.timestamp - 30 minutes;
        } else if (action == Types.ProtocolAction.Liquidation) {
            // for liquidation, simulate we got a recent timestamp
            ts = block.timestamp - 30 seconds;
        } else {
            // for other actions, simulate we got the price from 24s after the initiate action
            ts = targetTimestamp + _validationDelay;
        }
        // the timestamp cannot be in the future (the caller must `skip` before calling this function)
        require(ts < block.timestamp, "MockOracleMiddleware: timestamp is in the future");

        lastActionId = actionId;

        uint256 adjustedPrice = priceValue;
        if (_priceConfBps > 0) {
            adjustedPrice += priceValue * uint256(_priceConfBps) / BPS_DIVISOR;
        } else if (_priceConfBps < 0) {
            adjustedPrice -= priceValue * uint256(-_priceConfBps) / BPS_DIVISOR;
        }

        PriceInfo memory price = PriceInfo({ price: adjustedPrice, neutralPrice: priceValue, timestamp: ts });
        return price;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getDecimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function getValidationDelay() external view returns (uint256) {
        return _validationDelay;
    }

    /// @inheritdoc IBaseOracleMiddleware
    function validationCost(bytes calldata, Types.ProtocolAction) external view returns (uint256) {
        return _requireValidationCost ? 1 : 0;
    }

    function getConfRatioBps() external view returns (uint16) {
        return _confRatioBps;
    }

    function setValidationDelay(uint256 newDelay) external {
        _validationDelay = newDelay;
    }

    function setConfRatio(uint16 newConfRatio) external onlyRole(ADMIN_ROLE) {
        // confidence ratio limit check
        if (newConfRatio > MAX_CONF_RATIO) {
            revert IOracleMiddlewareErrors.OracleMiddlewareConfRatioTooHigh();
        }
        _confRatioBps = newConfRatio;
    }

    function setChainlinkTimeElapsedLimit(uint256 newTimeElapsedLimit) external {
        _timeElapsedLimit = newTimeElapsedLimit;
    }

    function setPythRecentPriceDelay(uint64) external { }

    function requireValidationCost() external view returns (bool) {
        return _requireValidationCost;
    }

    function setRequireValidationCost(bool req) external {
        _requireValidationCost = req;
    }

    function setPriceConfBps(int256 confBps) external {
        _priceConfBps = confBps;
    }

    function withdrawEther(address to) external {
        (bool success,) = payable(to).call{ value: address(this).balance }("");
        if (!success) {
            revert OracleMiddlewareTransferFailed(to);
        }
    }

    function getLowLatencyDelay() external pure returns (uint16) {
        return uint16(20 minutes);
    }

    function setLowLatencyDelay(uint16) external { }
}
