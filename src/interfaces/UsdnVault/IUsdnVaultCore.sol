// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/// @title USDN Vault core features
/// @notice This contract is the core of the USDN Vault.
/// @author @yahiru
/// @author @beeb
interface IUsdnVaultCore {
    /// @notice Update balances according to the current price.
    /// @param priceData The price data.
    function updateBalances(bytes calldata priceData) external payable;

    /// @notice PNL of long side since last price update.
    /// @dev The number is formatted with the same number of decimals as the price feed.
    /// @return pnl PNL of long side since last price update with same number of decimals as price feed.
    function pnlLong(uint128 price) external view returns (int256 pnl);

    /// @notice How much of the long balance needs to be transferred to short balance on next action.
    /// @dev A negative number means that some of the short balance needs to be transferred to the long balance.
    function fundingAsset(uint128 currentPrice, uint128 timestamp) external view returns (int256 fund);

    /// @notice Funding rate.
    /// @dev For each % of difference between longTradingExpo and shortTradingExpo, the funding rate is 0.03% per day.
    function funding(uint128 currentPrice, uint128 timestamp) external view returns (int256 fund);

    /// @notice Trading exposure of long side.
    /// @param currentPrice The current price.
    /// @return expo Trading exposure of long side.
    function longTradingExpo(uint128 currentPrice) external view returns (int256 expo);

    /// @notice Trading exposure of short side.
    /// @param currentPrice The current price.
    /// @return expo Trading exposure of short side.
    function shortTradingExpo(uint128 currentPrice) external view returns (int256 expo);

    /// @notice Asset available for long side.
    ///         Note: doesn't take into account the funding rate
    /// @param currentPrice The current price.
    /// @return available Asset available for long side.
    function longAssetAvailable(uint128 currentPrice) external view returns (int256 available);

    /// @notice Asset available for short side.
    ///        Note: doesn't take into account the funding rate
    /// @param currentPrice The current price.
    /// @return available Asset available for short side.
    function shortAssetAvailable(uint128 currentPrice) external view returns (int256 available);

    /// @notice Get the value of a long position.
    /// @param searchStart The tick to start searching from.
    /// @return tick The max initialized tick.
    function findMaxInitializedTick(int24 searchStart) external view returns (int24 tick);
}
