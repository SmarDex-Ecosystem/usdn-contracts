// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             External libraries                             */
/* -------------------------------------------------------------------------- */

/* -------------------------------- PaulRBerg ------------------------------- */

import { SD59x18 } from "@prb/math/src/SD59x18.sol";

/* ------------------------------ Open Zeppelin ----------------------------- */

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/* -------------------------------------------------------------------------- */
/*                              Internal imports                              */
/* -------------------------------------------------------------------------- */

import { TickMath } from "src/libraries/TickMath128.sol";
import { TickBitmap } from "src/libraries/TickBitmap.sol";
import { UsdnVaultStorage } from "./UsdnVaultStorage.sol";
import { IUsdnVaultCore } from "src/interfaces/IUsdnVaultCore.sol";
import { IOracleMiddleware, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

/* --------------------------------- Errors --------------------------------- */

import { TimestampTooOld } from "src/utils/Errors.sol";

contract UsdnVaultCore is IUsdnVaultCore, UsdnVaultStorage {
    // Safe ERC20 and Tick bitmap
    using SafeERC20 for IERC20Metadata;
    using TickBitmap for mapping(int16 => uint256);

    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Constructor.
    /// @param _asset The asset ERC20 contract.
    /// @param _oracleMiddleware The oracle middleware contract.
    /// @param _tickSpacing The positions tick spacing.
    constructor(IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing)
        UsdnVaultStorage(_asset, _oracleMiddleware, _tickSpacing)
    { }

    /// @notice Update balances according to the current price.
    /// @param priceData The price data.
    function updateBalances(bytes calldata priceData) external payable {
        PriceInfo memory currentPrice =
            oracleMiddleware.parseAndValidatePrice{ value: msg.value }(uint128(block.timestamp), 0, priceData);
        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
    }

    /// @notice PNL of long side since last price update.
    /// @dev The number is formatted with the same number of decimals as the price feed.
    /// @return pnl PNL of long side since last price update with same number of decimals as price feed.
    function pnlLong(uint128 price) public view returns (int256 pnl) {
        int256 priceDiff = int256(uint256(price)) - int256(uint256(lastPrice));
        pnl = (int256(totalExpo) * priceDiff) / int256(10 ** assetDecimals); // same decimals as price feed
    }

    /// @notice How much of the long balance needs to be transferred to short balance on next action.
    /// @dev A negative number means that some of the short balance needs to be transferred to the long balance.
    function fundingAsset(uint128 currentPrice, uint128 timestamp) public view returns (int256 fund) {
        fund = (-funding(currentPrice, timestamp) * longTradingExpo(currentPrice)) / int256(10) ** FUNDING_RATE_DECIMALS;
    }

    /// @notice Funding rate.
    /// @dev For each % of difference between longTradingExpo and shortTradingExpo, the funding rate is 0.03% per day.
    function funding(uint128 currentPrice, uint128 timestamp) public view returns (int256 fund) {
        if (timestamp < lastUpdateTimestamp) revert TimestampTooOld();

        int256 secondsElapsed = int256(uint256(timestamp - lastUpdateTimestamp));
        int256 shortExpo = shortTradingExpo(currentPrice);
        int256 longExpo = longTradingExpo(currentPrice);
        int256 relative = shortExpo > longExpo ? shortExpo : longExpo;
        fund = ((longExpo - shortExpo) * fundingRatePerSecond * secondsElapsed * 100) / relative;
    }

    /// @notice Trading exposure of long side.
    /// @param currentPrice The current price.
    /// @return expo Trading exposure of long side.
    function longTradingExpo(uint128 currentPrice) public view returns (int256 expo) {
        expo = int256(totalExpo) - longAssetAvailable(currentPrice);
    }

    /// @notice Trading exposure of short side.
    /// @param currentPrice The current price.
    /// @return expo Trading exposure of short side.
    function shortTradingExpo(uint128 currentPrice) public view returns (int256 expo) {
        expo = shortAssetAvailable(currentPrice);
    }

    /// @notice Asset available for long side.
    ///         Note: doesn't take into account the funding rate
    /// @param currentPrice The current price.
    /// @return available Asset available for long side.
    function longAssetAvailable(uint128 currentPrice) public view returns (int256 available) {
        // Cast to int256 to optimize gas usage
        int256 _totalExpo = int256(totalExpo);
        // Cast to int256 to optimize gas usage
        int256 _balanceLong = int256(balanceLong);

        // pnlAsset = (totalExpo - balanceLong) * pnlLong * 10^assetDecimals / (totalExpo * currentPrice)
        int256 pnlAsset = ((_totalExpo - _balanceLong) * pnlLong(currentPrice) * int256(10) ** assetDecimals)
            / (_totalExpo * int256(uint256(currentPrice)));

        available = _balanceLong + pnlAsset;
    }

    /// @notice Asset available for short side.
    ///        Note: doesn't take into account the funding rate
    /// @param currentPrice The current price.
    /// @return available Asset available for short side.
    function shortAssetAvailable(uint128 currentPrice) public view returns (int256 available) {
        available = int256(balanceShort + balanceLong) - longAssetAvailable(currentPrice);
    }

    /// @dev Apply PNL and funding to balances.
    /// @param currentPrice The current price.
    /// @param timestamp The timestamp.
    function _applyPnlAndFunding(uint128 currentPrice, uint128 timestamp) internal {
        if (timestamp <= lastUpdateTimestamp) {
            return;
        }
        uint256 totalBalance = balanceLong + balanceShort;
        int256 newLongBalance = longAssetAvailable(currentPrice) - fundingAsset(currentPrice, timestamp);
        if (newLongBalance < 0) {
            newLongBalance = 0;
        }
        int256 newShortBalance = int256(totalBalance) - newLongBalance;
        if (newShortBalance < 0) {
            newShortBalance = 0;
        }
        balanceLong = uint256(newLongBalance);
        balanceShort = uint256(newShortBalance);
        lastPrice = currentPrice;
        lastUpdateTimestamp = timestamp;
    }
}
