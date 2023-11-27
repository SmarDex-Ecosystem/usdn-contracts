// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Position } from "./IUsdnVault.sol";

/// @title USDN Vault Perps Interface
/// @notice This interface is used to interact with the USDN Vault perps.
/// @author @Yashiru
interface IUsdnVaultPerps {
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
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function openLong(uint96 _deposit, uint128 _liquidationPrice, bytes calldata _currentOraclePriceData)
        external
        payable
        returns (int24, uint256);

    /// @notice Commit a long entry.
    /// @param _deposit The amount of asset to deposit.
    /// @param _liquidationPrice The desired liquidation price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function openLong(
        uint96 _deposit,
        uint128 _liquidationPrice,
        bytes calldata _currentOraclePriceData,
        bytes calldata _previousActionPriceData
    ) external payable returns (int24, uint256);

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
    function deposit(uint128 deposit, bytes calldata _currentOraclePriceData) external payable;

    /// @notice Commit a short entry.
    /// @param deposit The amount of asset to deposit.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function deposit(uint128 deposit, bytes calldata _currentOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable;

    /* ------------------------------- Short exit ------------------------------- */

    /// @notice Commit a short exit.
    /// @param amount The amount of USDN to burn.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function withdraw(uint128 amount, bytes calldata _currentOraclePriceData) external payable;

    /// @notice Commit a short exit.
    /// @param amount The amount of USDN to burn.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    /// @param _previousActionPriceData The oracle data to retrive the previous action price.
    function withdraw(uint128 amount, bytes calldata _currentOraclePriceData, bytes calldata _previousActionPriceData)
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

    /// @notice Price of USDN for informational purposes
    /// @dev The number is formatted with the same number of decimals as the price feed.
    /// @return usdn Price of USDN with same number of decimals as price feed.
    function usdnPrice(uint128 currentPrice) external view returns (uint256 usdn);
}
