// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             External libraries                             */
/* -------------------------------------------------------------------------- */

/* ------------------------------ Open Zeppelin ----------------------------- */

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/* -------------------------------------------------------------------------- */
/*                              Internal imports                              */
/* -------------------------------------------------------------------------- */

import { TickBitmap } from "src/libraries/TickBitmap.sol";
import { TickMath } from "src/libraries/TickMath128.sol";
import { UsdnVaultStorage } from "./UsdnVaultStorage.sol";
import { IUsdnVaultCore } from "src/interfaces/UsdnVault/IUsdnVaultCore.sol";
import { IOracleMiddleware, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";

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

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnVaultCore
    function updateBalances(bytes calldata priceData) external payable {
        PriceInfo memory currentPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint128(block.timestamp), ProtocolAction.None, priceData
        );
        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /* --------------------------------- Funding -------------------------------- */

    /// @inheritdoc IUsdnVaultCore
    function fundingAsset(uint128 currentPrice, uint128 timestamp) public view returns (int256 fund) {
        fund = (-funding(currentPrice, timestamp) * longTradingExpo(currentPrice)) / int256(10) ** FUNDING_RATE_DECIMALS;
    }

    /// @inheritdoc IUsdnVaultCore
    function funding(uint128 currentPrice, uint128 timestamp) public view returns (int256 fund) {
        if (timestamp < lastUpdateTimestamp) revert TimestampTooOld();

        int256 secondsElapsed = int256(uint256(timestamp - lastUpdateTimestamp));
        int256 shortExpo = shortTradingExpo(currentPrice);
        int256 longExpo = longTradingExpo(currentPrice);
        int256 relative = shortExpo > longExpo ? shortExpo : longExpo;
        fund = ((longExpo - shortExpo) * fundingRatePerSecond * secondsElapsed * 100) / relative;
    }

    /// @inheritdoc IUsdnVaultCore
    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available)
    {
        available = longAssetAvailable(currentPrice) - fundingAsset(currentPrice, timestamp);
    }

    /// @inheritdoc IUsdnVaultCore
    function shortAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available)
    {
        available = shortAssetAvailable(currentPrice) + fundingAsset(currentPrice, timestamp);
    }

    /* -------------------------------- Positions ------------------------------- */

    /// @inheritdoc IUsdnVaultCore
    function pnlLong(uint128 price) public view returns (int256 pnl) {
        int256 priceDiff = int256(uint256(price)) - int256(uint256(lastPrice));
        pnl = (int256(totalExpo) * priceDiff) / int256(10 ** assetDecimals); // same decimals as price feed
    }
    /// @inheritdoc IUsdnVaultCore

    function longTradingExpo(uint128 currentPrice) public view returns (int256 expo) {
        expo = int256(totalExpo) - longAssetAvailable(currentPrice);
    }

    /// @inheritdoc IUsdnVaultCore
    function shortTradingExpo(uint128 currentPrice) public view returns (int256 expo) {
        expo = shortAssetAvailable(currentPrice);
    }

    /// @inheritdoc IUsdnVaultCore
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

    /// @inheritdoc IUsdnVaultCore
    function shortAssetAvailable(uint128 currentPrice) public view returns (int256 available) {
        available = int256(balanceShort + balanceLong) - longAssetAvailable(currentPrice);
    }

    /* ---------------------------------- Ticks --------------------------------- */

    /// @inheritdoc IUsdnVaultCore
    function findMaxInitializedTick(int24 searchStart) public view returns (int24 tick) {
        tick = searchStart + 1;
        uint256 i;
        do {
            unchecked {
                ++i;
            }
            (int24 next, bool initialized) = tickBitmap.nextInitializedTickWithinOneWord(tick - 1, tickSpacing, true);
            tick = next;
            if (!initialized) {
                // could not find a populated tick within 256 bits, continue looking
                continue;
            } else {
                break;
            }
        } while (true);
    }

    /// @inheritdoc IUsdnVaultCore
    function countInitializedTicks() public view returns (uint256 count) {
        int24 tick = maxInitializedTick + 1;
        do {
            (int24 next, bool initialized) = tickBitmap.nextInitializedTickWithinOneWord(tick - 1, tickSpacing, true);
            tick = next;
            if (tick <= TickMath.MIN_TICK) {
                break;
            }
            if (!initialized) {
                // could not find a populated tick within 256 bits, continue looking
                continue;
            }
            unchecked {
                ++count;
            }
        } while (true);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

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

    /// @dev Get the hash of a tick.
    /// @param tick The tick.
    /// @return The hash of the tick.
    function _tickHash(int24 tick) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(tick, tickVersion[tick]));
    }

    /// @dev Calculate the amount of USDN to mint for a deposit according to the current price.
    /// @param amount The amount of asset to deposit.
    /// @param currentPrice The current price.
    /// @return toMint The amount of USDN to mint.
    function _calcMintUsdp(uint256 amount, uint128 currentPrice) internal view returns (uint256 toMint) {
        toMint = (amount * currentPrice) / 10 ** (assetDecimals + priceFeedDecimals - usdn.decimals());
    }
}
