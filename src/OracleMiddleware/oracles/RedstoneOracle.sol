// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// Temporary measure, forked the contracts to remove dependency on safemath
import { PrimaryProdDataServiceConsumerBase } from
    "src/vendored/Redstone/data-services/PrimaryProdDataServiceConsumerBase.sol";

import { IOracleMiddlewareErrors } from "src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { RedstonePriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @title Redstone Oracle
 * @notice This contract is used to validate asset prices coming from the Redstone oracle
 * It is used by the USDN protocol to get the price of the underlying asset
 */
abstract contract RedstoneOracle is PrimaryProdDataServiceConsumerBase, IOracleMiddlewareErrors {
    /// @notice Interval between two Redstone price updates
    uint48 public constant REDSTONE_HEARTBEAT = 10 seconds;

    /// @notice Number of decimals for prices contained in Redstone price updates
    uint8 public constant REDSTONE_DECIMALS = 8;

    /// @notice The ID of the Redstone price feed
    bytes32 internal immutable _redstoneFeedId;

    /// @notice The maximum age of a recent price to be considered valid
    uint48 internal _redstoneRecentPriceDelay = 45 seconds;

    /// @param redstoneFeedId The ID of the price feed
    constructor(bytes32 redstoneFeedId) {
        _redstoneFeedId = redstoneFeedId;
    }

    function getRedstoneFeedId() external view returns (bytes32) {
        return _redstoneFeedId;
    }

    function getRedstoneRecentPriceDelay() external view returns (uint48) {
        return _redstoneRecentPriceDelay;
    }

    function validateTimestamp(uint256) public pure override {
        // disable default timestamp validation, we accept everything during extraction
        return;
    }

    function _getFormattedRedstonePrice(uint128 targetTimestamp, uint256 middlewareDecimals)
        internal
        view
        returns (RedstonePriceInfo memory formattedPrice_)
    {
        formattedPrice_.timestamp = _extractPriceUpdateTimestamp();
        if (targetTimestamp == 0) {
            // we want to validate that the price is recent
            if (formattedPrice_.timestamp < block.timestamp - _redstoneRecentPriceDelay) {
                revert OracleMiddlewarePriceTooOld(formattedPrice_.timestamp);
            }
        } else {
            // we want to validate that the price is in a 10-seconds window starting at the target timestamp
            if (formattedPrice_.timestamp < targetTimestamp) {
                revert OracleMiddlewarePriceTooOld(formattedPrice_.timestamp);
            } else if (formattedPrice_.timestamp >= targetTimestamp + REDSTONE_HEARTBEAT) {
                revert OracleMiddlewarePriceTooRecent(formattedPrice_.timestamp);
            }
        }
        uint256 price = getOracleNumericValueFromTxMsg(_redstoneFeedId);
        if (price == 0) {
            revert OracleMiddlewareWrongPrice(0);
        }
        formattedPrice_.price = price * 10 ** middlewareDecimals / 10 ** REDSTONE_DECIMALS;
    }

    function _extractPriceUpdateTimestamp() internal pure returns (uint48 extractedTimestamp_) {
        uint256 calldataNegativeOffset = _extractByteSizeOfUnsignedMetadata();
        calldataNegativeOffset += DATA_PACKAGES_COUNT_BS;
        uint256 timestampCalldataOffset =
            msg.data.length - (calldataNegativeOffset + TIMESTAMP_NEGATIVE_OFFSET_IN_DATA_PACKAGE_WITH_STANDARD_SLOT_BS);
        assembly {
            // this is in milliseconds
            extractedTimestamp_ := calldataload(timestampCalldataOffset)
            // convert to seconds
            extractedTimestamp_ := div(extractedTimestamp_, 1000)
        }
    }
}
