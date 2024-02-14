// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title IUsdnProtocolEvents
 * @notice Events for the USDN Protocol
 */
interface IUsdnProtocolEvents {
    /**
     * @notice Emitted when a user initiates a deposit.
     * @param user The user address.
     * @param amount The amount of asset that were deposited.
     */
    event InitiatedDeposit(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user validates a deposit.
     * @param user The user address.
     * @param amountDeposited The amount of asset that were deposited.
     * @param usdnMinted The amount of USDN that were minted.
     */
    event ValidatedDeposit(address indexed user, uint256 amountDeposited, uint256 usdnMinted);

    /**
     * @notice Emitted when a user initiates a withdrawal.
     * @param user The user address.
     * @param usdnAmount The amount of USDN that will be burned.
     */
    event InitiatedWithdrawal(address indexed user, uint256 usdnAmount);

    /**
     * @notice Emitted when a user validates a withdrawal.
     * @param user The user address.
     * @param amountWithdrawn The amount of asset that were withdrawn.
     * @param usdnBurned The amount of USDN that were burned.
     */
    event ValidatedWithdrawal(address indexed user, uint256 amountWithdrawn, uint256 usdnBurned);

    /**
     * @notice Emitted when a user initiates the opening of a long position.
     * @dev The combination of the tick number, the tick version, and the index constitutes a unique identifier for the
     * position.
     * @param user The user address.
     * @param position The position that was opened (pending validation).
     * @param tick The tick containing the position.
     * @param tickVersion The tick version.
     * @param index The index of the position inside the tick array.
     */
    event InitiatedOpenPosition(
        address indexed user, Position position, int24 tick, uint256 tickVersion, uint256 index
    );

    /**
     * @notice Emitted when a user validates the opening of a long position.
     * @param user The user address.
     * @param position The position that was opened (final).
     * @param tick The tick containing the position.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted
     * @param tickVersion The tick version.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted
     * @param index The index of the position inside the tick array.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted
     * @param liquidationPrice The liquidation price of the position (final).
     */
    event ValidatedOpenPosition(
        address indexed user,
        Position position,
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        uint128 liquidationPrice
    );

    /**
     * @notice Emitted when a position was moved from one tick to another.
     * @param oldTick The old tick of the position.
     * @param oldTickVersion The old tick version.
     * @param oldIndex The old index of the position inside the tick array.
     * @param newTick The new tick containing the position.
     * @param newTickVersion The new tick version.
     * @param newIndex The new index of the position inside the `newTick` array.
     */
    event LiquidationPriceChanged(
        int24 indexed oldTick,
        uint256 indexed oldTickVersion,
        uint256 indexed oldIndex,
        int24 newTick,
        uint256 newTickVersion,
        uint256 newIndex
    );

    /**
     * @notice Emitted when a user initiates the closing of a long position.
     * @param user The user address.
     * @param tick The tick containing the position.
     * @param tickVersion The tick version.
     * @param index The index of the position inside the tick array.
     */
    event InitiatedClosePosition(address indexed user, int24 tick, uint256 tickVersion, uint256 index);

    /**
     * @notice Emitted when a user validates the closing of a long position
     * @param user The user address.
     * @param tick The tick that was containing the position.
     * @param tickVersion The tick version.
     * @param index The index that the position had inside the tick array.
     * @param amountReceived The amount of asset that were sent to the user.
     * @param profit The profit that the user made.
     */
    event ValidatedClosePosition(
        address indexed user, int24 tick, uint256 tickVersion, uint256 index, uint256 amountReceived, int256 profit
    );

    /**
     * @notice Emitted when a tick is liquidated
     * @param tick The liquidated tick.
     * @param oldTickVersion The liquidated tick version.
     * @param liquidationPrice The asset price at the moment of liquidation.
     * @param effectiveTickPrice The effective liquidated tick price.
     */
    event LiquidatedTick(
        int24 indexed tick, uint256 indexed oldTickVersion, uint256 liquidationPrice, uint256 effectiveTickPrice
    );

    /**
     * @notice Emitted when a position is individually liquidated
     * @param user The user address.
     * @param tick The tick that was containing the position.
     * @param tickVersion The tick version.
     * @param index The index that the position had inside the tick array.
     * @param liquidationPrice The asset price at the moment of liquidation.
     * @param effectiveTickPrice The effective liquidated tick price.
     */
    event LiquidatedPosition(
        address indexed user,
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        uint256 liquidationPrice,
        uint256 effectiveTickPrice
    );

    /**
     * @notice Emitted when a user's position was liquidated while pending validation and we remove the pending action.
     * @param user The user address.
     * @param tick The tick that contained the position.
     * @param tickVersion The tick version when the position was created.
     * @param index The index of the position inside the tick array.
     */
    event StalePendingActionRemoved(address indexed user, int24 tick, uint256 tickVersion, uint256 index);

    /**
     * @notice Emitted when a user (liquidator) successfully liquidated positions.
     * @param liquidator The address that inittiated the liquidation.
     * @param rewards The amount of tokens the liquidator received in rewards.
     */
    event LiquidatorRewarded(address indexed liquidator, uint256 rewards);

    /**
     * @notice Emitted when the LiquidationRewardsManager contract is updated.
     * @param newAddress The address of the new (current) contract.
     */
    event LiquidationRewardsManagerUpdated(address newAddress);
}
