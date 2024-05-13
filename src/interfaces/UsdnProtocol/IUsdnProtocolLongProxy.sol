// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolCommon } from "src/interfaces/UsdnProtocol/IUsdnProtocolCommon.sol";
import { Position, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PreviousActionsData, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolLong
 * @notice Interface for the long side layer of the USDN protocol.
 */
interface IUsdnProtocolLongProxy is IUsdnProtocolCommon {
    /**
     * @notice Get the value of the highest usable tick, taking into account the tick spacing
     * @dev Note that the effective maximum tick of a newly open long position also depends on the maximum allowed
     * leverage value and the current value of the liquidation price multiplier.
     */
    function maxTick() external view returns (int24);

    /**
     * @notice Get a long position identified by its tick, tickVersion and index
     * @param posId The unique position identifier
     * @return pos_ The position data
     * @return liquidationPenalty_ The liquidation penalty for that position (and associated tick)
     */
    function getLongPosition(PositionId calldata posId)
        external
        view
        returns (Position memory pos_, uint8 liquidationPenalty_);

    /**
     * @notice Get the minimum acceptable desired liquidation price for a new long position
     * @dev This takes into account the current value of the liquidation price multiplier and the minimum leverage value
     * @param price The current asset price
     */
    function getMinLiquidationPrice(uint128 price) external view returns (uint128);

    /**
     * @notice Get the value of a long position when the asset price is equal to the given price, at the given timestamp
     * @dev If the current price is smaller than the liquidation price of the position without liquidation penalty,
     * then the value of the position is negative.
     * @param posId The unique position identifier
     * @param price The asset price
     * @param timestamp The timestamp of the price
     * @return The position value in assets
     */
    function getPositionValue(PositionId calldata posId, uint128 price, uint128 timestamp)
        external
        view
        returns (int256);

    function funding(uint128 timestamp) external view returns (int256 fund_, int256 oldLongExpo_);

    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        returns (uint256 validatedActions_);

    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidatedPositions_);

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp) external view returns (int256);

    function _checkImbalanceLimitOpen(uint256 openTotalExpoValue, uint256 openCollatValue) external view;

    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable returns (PositionId memory posId_);

    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;

    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable;

    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;
}
