// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                                   Structs                                  */
/* -------------------------------------------------------------------------- */

/// @dev 32 bytes packed struct representing a position waiting for a commitment.
///      It can be a short entry, a short exit, a long entry or a long exit.
/// NOTE: The leverage is 0 if the position is a short.
struct Position {
    uint40 leverage; // Max 1_099_511_627_775 (1_099 with 9 decimals)
    uint40 timestamp; // Max 1_099_511_627_775 (20/02/36812 01:36:15)
    bool isExit;
    bool validated;
    address user;
    uint128 amount;
    uint128 startPrice;
}

/// @dev 32 bytes packed struct representing the metadata of a position waiting
///      for a commitment.
struct PendingPositionMetadata {
    int24 tick;
    uint64 gasPrice;
    uint168 index;
}

/// @title USDN Vault
/// @notice This contract is the USDN Vault.
/// @dev This contract is used to manage the long and short positions.
/// @author @yahiru
/// @author @beeb
interface IUsdnVault {
    /* -------------------------------------------------------------------------- */
    /*                               View functions                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Asset available for long side with funding rate.
    ///         Note: take into account the funding rate
    /// @param currentPrice The current price.
    /// @param timestamp The timestamp.
    /// @return available Asset available for long side with funding rate.
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 available);

    /// @notice Asset available for short side with funding rate.
    ///         Note: take into account the funding rate
    /// @param currentPrice The current price.
    /// @param timestamp The timestamp.
    /// @return available Asset available for short side with funding rate.
    function shortAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 available);

    /// @notice Get the liquidation price of a long position.
    /// @param tick The position.
    /// @param index The position index.
    /// @return price The liquidation price.
    function getLiquidationPrice(int24 tick, uint256 index) external view returns (uint128 price);

    /// @notice Get the value of a long position.
    /// @param searchStart The tick to start searching from.
    /// @return tick The max initialized tick.
    function findMaxInitializedTick(int24 searchStart) external view returns (int24 tick);

    /// @notice Get the number of initialized ticks.
    /// @return count The number of initialized ticks.
    function countInitializedTicks() external view returns (uint256 count);

    /// @notice Get the profit and loss of a long position.
    /// @param tick The position.
    /// @param index The position index.
    /// @param currentPrice The current price.
    /// @return pnl The profit and loss.
    function positionPnl(int24 tick, uint256 index, uint128 currentPrice) external view returns (int256 pnl);

    /// @notice Get the value of a long position.
    /// @param tick The position.
    /// @param index The position index.
    /// @param currentPrice The current price.
    /// @return value The value.
    function positionValue(int24 tick, uint256 index, uint128 currentPrice) external view returns (int256 value);

    /* -------------------------------------------------------------------------- */
    /*                               Pure functions                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Get the profit and loss of a long position.
    /// @param currentPrice The current price.
    /// @param startPrice The start price of the position.
    /// @param amount The amount of the position.
    /// @param leverage The leverage of the position.
    /// @return pnl The profit and loss.
    function positionPnl(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        external
        pure
        returns (int256 pnl);

    /// @notice Get the value of a long position.
    /// @param currentPrice The current price.
    /// @param startPrice The start price of the position.
    /// @param amount The amount of the position.
    /// @param leverage The leverage of the position.
    /// @return value The value.
    function positionValue(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        external
        pure
        returns (int256 value);

    /// @notice Get the liquidation price of a long position.
    /// @param startPrice The start price of the position.
    /// @param leverage The leverage of the position.
    /// @return price The liquidation price.
    function getLiquidationPrice(uint128 startPrice, uint40 leverage) external pure returns (uint128 price);

    /// @notice Get the leverage of a long position.
    /// @param startPrice The start price of the position.
    /// @param liquidationPrice The liquidation price of the position.
    /// @return leverage The leverage.
    function getLeverage(uint128 startPrice, uint128 liquidationPrice) external pure returns (uint40 leverage);

    /* -------------------------------------------------------------------------- */
    /*                            Only owner functions                            */
    /* -------------------------------------------------------------------------- */

    /// @notice Initialize the vault.
    /// @dev To be called once the vault is authorized to transfer the asset.
    function initialize(uint256 _depositShort, uint96 _depositLong, uint128 _currentPrice) external;

    /// @notice Manually set the funding rate.
    /// @param _fundingRatePerSecond The new funding rate.
    function setFundingRate(int256 _fundingRatePerSecond) external;

    /// @notice Set the min and max leverage.
    /// @param _minLeverage The new min leverage.
    /// @param _maxLeverage The new max leverage.
    function setMinMaxLeverage(uint256 _minLeverage, uint256 _maxLeverage) external;

    /// @notice Set the oracle middleware address.
    /// @param _oracleMiddleware The new oracle middleware address.
    function setOracleMiddleware(address _oracleMiddleware) external;
}
