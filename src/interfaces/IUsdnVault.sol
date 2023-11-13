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
    /*                               Opened features                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Liquidate all positions in a tick.
    ///         Note: MaxIter is used to limit the number of iterations.
    /// @param maxIter The maximum number of iterations.
    /// @param priceData The price data.
    /// @return liquidated The number of liquidated positions.
    function liquidate(uint256 maxIter, bytes calldata priceData) external payable returns (uint256 liquidated);

    /* -------------------------------------------------------------------------- */
    /*                                Long features                               */
    /* -------------------------------------------------------------------------- */

    /* ------------------------------- Long entry ------------------------------- */

    /// @notice Commit a long entry.
    /// @param _deposit The amount of asset to deposit.
    /// @param _liquidationPrice The desired liquidation price.
    function openLong(uint96 _deposit, uint128 _liquidationPrice) external payable returns (int24, uint256);

    /// @notice Commit a long entry.
    /// @param _deposit The amount of asset to deposit.
    /// @param _liquidationPrice The desired liquidation price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function openLong(uint96 _deposit, uint128 _liquidationPrice, bytes calldata _previousActionPriceData)
        external
        payable
        returns (int24, uint256);

    /* -------------------------------- Long exit ------------------------------- */

    /// @notice Commit a long exit.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function closeLong(int24 _tick, uint256 _index, bytes calldata _currentOraclePriceData)
        external
        payable
        returns (int24, uint256);

    /// @notice Commit a long exit.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function closeLong(
        int24 _tick,
        uint256 _index,
        bytes calldata _currentOraclePriceData,
        bytes calldata _previousActionPriceData
    ) external payable returns (int24, uint256);

    /* ----------------------------- Long validation ---------------------------- */

    /// @notice Validate a long position that has not benn validated yet.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _finalOraclePriceData The oracle data to retrive the final validated price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function validateLong(
        int24 _tick,
        uint256 _index,
        bytes calldata _finalOraclePriceData,
        bytes calldata _previousActionPriceData
    ) external payable;

    /// @notice Validate a long position that has not benn validated yet.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _finalOraclePriceData The oracle data to retrive the final validated price.
    function validateLong(int24 _tick, uint256 _index, bytes calldata _finalOraclePriceData) external payable;

    /* -------------------------------------------------------------------------- */
    /*                               Short features                               */
    /* -------------------------------------------------------------------------- */

    /* ------------------------------- Short entry ------------------------------ */

    /// @notice Commit a short entry.
    /// @param deposit The amount of asset to deposit.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function openShort(uint128 deposit, bytes calldata _currentOraclePriceData) external payable;

    /// @notice Commit a short entry.
    /// @param deposit The amount of asset to deposit.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function openShort(uint128 deposit, bytes calldata _currentOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable;

    /* ------------------------------- Short exit ------------------------------- */

    /// @notice Commit a short exit.
    /// @param amount The amount of USDP to burn.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function closeShort(uint128 amount, bytes calldata _currentOraclePriceData) external payable;

    /// @notice Commit a short exit.
    /// @param amount The amount of USDP to burn.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function closeShort(uint128 amount, bytes calldata _currentOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable;

    /* ---------------------------- Short validation ---------------------------- */

    /// @notice Validate a short position that has not benn validated yet.
    /// @param _finalOraclePriceData The oracle data to retrive the final validated price.
    function validateShort(bytes calldata _finalOraclePriceData) external payable;

    /// @notice Validate a short position that has not benn validated yet.
    /// @param _finalOraclePriceData The oracle data to retrive the final validated price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function validateShort(bytes calldata _finalOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable;

    /* -------------------------------------------------------------------------- */
    /*                               View functions                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Get a long position.
    /// @param tick The position.
    /// @param index The position index.
    /// @return pos The position.
    function getLongPosition(int24 tick, uint256 index) external view returns (Position memory pos);

    /// @notice Get the long positions count in a tick.
    /// @param tick The position.
    /// @return len The long positions count.
    function getLongPositionsLength(int24 tick) external view returns (uint256 len);

    /// @notice Price of USDP for informational purposes
    /// @dev The number is formatted with the same number of decimals as the price feed.
    /// @return usdp Price of USDP with same number of decimals as price feed.
    function usdpPrice(uint128 currentPrice) external view returns (uint256 usdp);

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
