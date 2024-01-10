// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                              Structs and enums                             */
/* -------------------------------------------------------------------------- */

/**
 * @notice Information about a long user position.
 * @dev 64 bytes packed struct (512 bits)
 * @param leverage The leverage of the position (0 for vault deposits).
 * @param timestamp The timestamp of the position start.
 * @param user The user address.
 * @param amount The amount of the position.
 * @param startPrice The price of the asset at the position opening.
 */
struct Position {
    uint40 leverage; // 5 bytes. Max 1_099_511_627_775 (1_099 with 9 decimals)
    uint40 timestamp; // 5 bytes. Max 1_099_511_627_775 (36812-02-20 01:36:15)
    address user; // 20 bytes
    uint128 amount; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 wstETH
    uint128 startPrice; // 16 bytes. Max 340_282_366_920_938_463_463.374_607_431_768_211_455 USD/wstETH
}

/**
 * @notice All possible action types for the protocol.
 * @dev This is used for pending actions and to interact with the oracle middleware.
 * @param None No particular action.
 * @param Initialize The contract is being initialized.
 * @param InitiateDeposit Initiating a deposit action.
 * @param ValidateDeposit Validating a deposit action.
 * @param InitiateWithdrawal Initiating a withdraw action.
 * @param ValidateWithdrawal Validating a withdraw action.
 * @param InitiateOpenPosition Initiating an open position action.
 * @param ValidateOpenPosition Validating an open position action.
 * @param InitiateClosePosition Initiating a close position action.
 * @param ValidateClosePosition Validating a close position action.
 * @param Liquidation The price is requested for a liquidation action.
 */
enum ProtocolAction {
    None,
    Initialize,
    InitiateDeposit,
    ValidateDeposit,
    InitiateWithdrawal,
    ValidateWithdrawal,
    InitiateOpenPosition,
    ValidateOpenPosition,
    InitiateClosePosition,
    ValidateClosePosition,
    Liquidation
}

/**
 * @notice A pending deposit action.
 * @param action The action type (Initiate...).
 * @param timestamp The timestamp of the initiate action.
 * @param user The user address.
 * @param tick The tick for open/close long (zero for vault actions).
 * @param amountOrIndex The amount for deposit/withdraw, or index inside the tick for open/close long.
 */
struct PendingAction {
    ProtocolAction action; // 1 byte
    uint40 timestamp; // 5 bytes
    address user; // 20 bytes
    int24 tick; // 3 bytes, tick for open/close long
    uint256 amountOrIndex; // 32 bytes, amount for deposit/withdraw, or index inside the tick for open/close long
}

/* -------------------------------------------------------------------------- */
/*                                   Events                                   */
/* -------------------------------------------------------------------------- */

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
     * @param user The user address.
     * @param position The position that was opened (pending validation).
     * @param tick The tick containing the position.
     * @param index The index of the position inside the tick array.
     */
    event InitiatedOpenPosition(address indexed user, Position position, int24 tick, uint256 index);

    /**
     * @notice Emitted when a user validates the opening of a long position.
     * @param user The user address.
     * @param position The position that was opened (final).
     * @param tick The tick containing the position.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted
     * @param index The index of the position inside the tick array.
     * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceChanged` will be emitted
     * @param liquidationPrice The liquidation price of the position (final).
     */
    event ValidatedOpenPosition(
        address indexed user, Position position, int24 tick, uint256 index, uint128 liquidationPrice
    );

    /**
     * @notice Emitted when a position was moved from one tick to another.
     * @param oldTick The old tick of the position.
     * @param oldIndex The old index of the position inside the tick array.
     * @param newTick The new tick containing the position.
     * @param newIndex The new index of the position inside the `newTick` array.
     */
    event LiquidationPriceChanged(int24 indexed oldTick, uint256 indexed oldIndex, int24 newTick, uint256 newIndex);

    /**
     * @notice Emitted when a user initiates the closing of a long position.
     * @param user The user address.
     * @param tick The tick containing the position.
     * @param index The index of the position inside the tick array.
     */
    event InitiatedClosePosition(address indexed user, int24 tick, uint256 index);

    /**
     * @notice Emitted when a user validates the closing of a long position
     * @param user The user address.
     * @param tick The tick that was containing the position.
     * @param index The index that the position had inside the tick array.
     * @param amountReceived The amount of asset that were sent to the user.
     * @param profit The profit that the user made.
     */
    event ValidatedClosePosition(
        address indexed user, int24 tick, uint256 index, uint256 amountReceived, int256 profit
    );
}

/* -------------------------------------------------------------------------- */
/*                                   Errors                                   */
/* -------------------------------------------------------------------------- */

interface IUsdnProtocolErrors {
    /// @dev Indicates that the provided amount is zero
    error UsdnProtocolZeroAmount();

    /// @dev Indicates that the initilization deposit is too low
    error UsdnProtocolMinInitAmount(uint256 minInitAmount);

    /// @dev Indicates that the provided USDN contract has a total supply above zero at deployment
    error UsdnProtocolInvalidUsdn(address usdnAddress);

    /// @dev Indicates that the user is not allowed to perform an action
    error UsdnProtocolUnauthorized();

    /// @dev Indicates that the the token transfer didn't yield the expected balance change
    error UsdnProtocolIncompleteTransfer(address to, uint256 effectiveBalance, uint256 expectedBalance);

    /// @dev Indicates that the user already has a pending action
    error UsdnProtocolPendingAction();

    /// @dev Indicates that the user has no pending action
    error UsdnProtocolNoPendingAction();

    /// @dev Indicates that the user has a pending action but its action type is not the expected one
    error UsdnProtocolInvalidPendingAction();

    /// @dev Indicates that the provided timestamp is too old (pre-dates the last balances update)
    error UsdnProtocolTimestampTooOld();

    /// @dev Indicates that the provided collateral and liquidation price result in a leverage that is too low
    error UsdnProtocolLeverageTooLow();

    /// @dev Indicates that the provided collateral and liquidation price result in a leverage that is too high
    error UsdnProtocolLeverageTooHigh();

    /// @dev Indicates that the liquidation price is higher than or equal to the start price
    error UsdnProtocolInvalidLiquidationPrice(uint128 liquidationPrice, uint128 startPrice);

    /// @dev Indicates that the liquidation price exceeds the safety margin
    error UsdnProtocolLiquidationPriceSafetyMargin(uint128 liquidationPrice, uint128 maxLiquidationPrice);
}
