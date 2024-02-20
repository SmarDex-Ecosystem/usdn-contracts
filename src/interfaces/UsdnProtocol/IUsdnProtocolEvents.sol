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
     * @param timestamp The timestamp of the action.
     * @param leverage The initial leverage of the position (pending validation).
     * @param amount The amount of asset that were deposited as collateral.
     * @param startPrice The asset price at the moment of the position creation (pending validation).
     * @param tick The tick containing the position.
     * @param tickVersion The tick version.
     * @param index The index of the position inside the tick array.
     */
    event InitiatedOpenPosition(
        address indexed user,
        uint40 timestamp,
        uint128 leverage,
        uint128 amount,
        uint128 startPrice,
        int24 tick,
        uint256 tickVersion,
        uint256 index
    );

    /**
     * @notice Emitted when a user validates the opening of a long position.
     * @param user The user address.
     * @param newLeverage The initial leverage of the position (final).
     * @param newStartPrice The asset price at the moment of the position creation (final).
     * @param tick The tick containing the position.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted too
     * @param tickVersion The tick version.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted too
     * @param index The index of the position inside the tick array.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted too
     */
    event ValidatedOpenPosition(
        address indexed user, uint128 newLeverage, uint128 newStartPrice, int24 tick, uint256 tickVersion, uint256 index
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
     * @param remainingCollateral The amount of asset that was left in the tick, which was transferred to the vault if
     * positive, or was taken from the vault if negative.
     */
    event LiquidatedTick(
        int24 indexed tick,
        uint256 indexed oldTickVersion,
        uint256 liquidationPrice,
        uint256 effectiveTickPrice,
        int256 remainingCollateral
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
     * @notice Emitted when the protocol fees are updated.
     * @param protocolFee The new protocol fee (in percentage).
     */
    event UpdatedProtocolFees(uint256 protocolFee);

    /**
     * @notice Emitted when the protocol fee decimals are updated.
     * @param protocolFeeDecimals The new protocol fee decimals.
     */
    event UpdatedProtocolFeeDecimals(uint256 protocolFeeDecimals);

    /**
     * @notice Emitted when the pending protocol fee is distributed.
     * @param feeCollector The collector address.
     * @param amount The amount of fee transferred.
     */
    event ProtocolFeeDistributed(address feeCollector, uint256 amount);

    /**
     * @notice Emitted when the protocol fee is updated.
     * @param feeBps The new fee in basis points.
     */
    event FeeBpsUpdated(uint256 feeBps);

    /**
     * @notice Emitted when the fee collector is updated.
     * @param feeCollector The new fee collector address.
     */
    event FeeCollectorUpdated(address feeCollector);

    /**
     * @notice Emitted when the fee threshold is updated.
     * @param feeThreshold The new fee threshold.
     */
    event FeeThresholdUpdated(uint256 feeThreshold);
}
