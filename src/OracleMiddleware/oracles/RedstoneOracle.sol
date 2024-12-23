// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// Temporary measure, forked the contracts to remove dependency on safemath

import { IOracleMiddlewareErrors } from "../../interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { RedstonePriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IRedstoneOracle } from "../../interfaces/OracleMiddleware/IRedstoneOracle.sol";
import { RedstoneConsumerBase } from "@redstone-finance/evm-connector/contracts/core/RedstoneConsumerBase.sol";
import { PrimaryProdDataServiceConsumerBase } from
    "@redstone-finance/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";

/**
 * @title Contract To Communicate With The Redstone Oracle
 * @notice This contract is used to get the price of the asset that corresponds to the stored feed ID.
 * @dev Is implemented by the {OracleMiddlewareWithRedstone} contract.
 */
abstract contract RedstoneOracle is IRedstoneOracle, PrimaryProdDataServiceConsumerBase, IOracleMiddlewareErrors {
    /// @inheritdoc IRedstoneOracle
    uint48 public constant REDSTONE_HEARTBEAT = 10 seconds;

    /// @inheritdoc IRedstoneOracle
    uint8 public constant REDSTONE_DECIMALS = 8;

    /// @notice The ID of the Redstone price feed.
    bytes32 internal immutable _redstoneFeedId;

    /// @notice The maximum age of a price to be considered recent.
    uint48 internal _redstoneRecentPriceDelay = 45 seconds;

    /// @param redstoneFeedId The ID of the price feed.
    constructor(bytes32 redstoneFeedId) {
        _redstoneFeedId = redstoneFeedId;
    }

    /// @inheritdoc IRedstoneOracle
    function getRedstoneFeedId() external view returns (bytes32 feedId_) {
        return _redstoneFeedId;
    }

    /// @inheritdoc IRedstoneOracle
    function getRedstoneRecentPriceDelay() external view returns (uint48 delay_) {
        return _redstoneRecentPriceDelay;
    }

    /// @inheritdoc IRedstoneOracle
    function validateTimestamp(uint256) public pure override(IRedstoneOracle, RedstoneConsumerBase) {
        // disable default timestamp validation, we accept everything during extraction
        return;
    }

    /**
     * @notice Gets the price of the asset from Redstone, formatted to the specified number of decimals.
     * @dev Redstone automatically retrieves data from the end of the calldata, no need to pass the pointer.
     * @param targetTimestamp The target timestamp to validate the price. If zero, then we accept a price as old as
     * `block.timestamp - _redstoneRecentPriceDelay`.
     * @param middlewareDecimals The number of decimals to format the price to.
     * @return formattedPrice_ The price from Redstone, normalized to `middlewareDecimals`.
     */
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
            // we want to validate that the price is in a 1-heartbeat window starting at the target timestamp
            if (formattedPrice_.timestamp < targetTimestamp) {
                revert OracleMiddlewarePriceTooOld(formattedPrice_.timestamp); // price is too much before the target
            } else if (formattedPrice_.timestamp >= targetTimestamp + REDSTONE_HEARTBEAT) {
                revert OracleMiddlewarePriceTooRecent(formattedPrice_.timestamp); // price is too much after the target
            }
        }
        uint256 price = getOracleNumericValueFromTxMsg(_redstoneFeedId);
        if (price == 0) {
            revert OracleMiddlewareWrongPrice(0);
        }
        formattedPrice_.price = price * 10 ** middlewareDecimals / 10 ** REDSTONE_DECIMALS;
    }

    /**
     * @notice Extract the timestamp from the price update.
     * @dev `extractedTimestamp_` is a timestamp in seconds.
     * @return extractedTimestamp_ The timestamp of the price update.
     */
    function _extractPriceUpdateTimestamp() internal pure returns (uint48 extractedTimestamp_) {
        extractedTimestamp_ = uint48(extractTimestampsAndAssertAllAreEqual() / 1000);
    }
}
