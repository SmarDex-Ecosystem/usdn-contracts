// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./PreconditionsBase.sol";

abstract contract PreconditionsAdmin is PreconditionsBase {
    enum PriceMode {
        NORMAL,
        ANTI_LIQUIDATION,
        SWING
    }

    struct SetPricePreconditions {
        int256 currentPrice;
        int256 newPrice;
        int256 minAllowedPrice;
        int256 maxAllowedPrice;
    }

    PriceMode internal currentMode = PriceMode.NORMAL;
    uint256 internal swingModeCallCount = 0;

    function setPriceMode() internal {
        if (usdnProtocol.checkNumOfPositions() < 7) {
            currentMode = PriceMode.ANTI_LIQUIDATION;
        } else {
            currentMode = PriceMode.SWING;
        }
    }

    function setPricePreconditions(int256 priceChangePercent) internal returns (SetPricePreconditions memory) {
        setPriceMode();

        (, int256 currentPrice,,,) = chainlink.latestRoundData();
        currentPrice = currentPrice / int256(10 ** chainlink.decimals());

        int256 maxChangePercent = INT_MAX_CHANGE_BP;
        int256 newPrice;

        if (currentMode == PriceMode.SWING) {
            swingModeCallCount++;
            if (swingModeCallCount % 10 == 0) {
                // Large swing every 10 calls, currently 3%
                maxChangePercent = SWING_MODE_LARGE_MAX_CHANGE;
            } else {
                // Normal swing for other calls, 10%
                maxChangePercent = SWING_MODE_NORMAL_MAX_CHANGE;
            }
        }

        int256 clampedChangePercent = fl.clamp(priceChangePercent, -maxChangePercent, maxChangePercent);

        int256 priceChange = (currentPrice * clampedChangePercent) / INT_ONE_HUNDRED_BP;

        newPrice = currentPrice + priceChange;

        if (newPrice < MIN_ORACLE_PRICE) {
            newPrice = MIN_ORACLE_PRICE;
        }

        if (currentMode == PriceMode.ANTI_LIQUIDATION && newPrice < int256(uint256(initialLongPositionPrice)) / 1e18) {
            newPrice = int256(uint256(initialLongPositionPrice + 1e18) / 1e18);
        }

        int256 minAllowedPrice = (currentPrice * (INT_ONE_HUNDRED_BP - maxChangePercent)) / INT_ONE_HUNDRED_BP;
        int256 maxAllowedPrice = (currentPrice * (INT_ONE_HUNDRED_BP + maxChangePercent)) / INT_ONE_HUNDRED_BP;

        if (currentMode == PriceMode.SWING) { }

        return SetPricePreconditions({
            currentPrice: currentPrice,
            newPrice: newPrice,
            minAllowedPrice: minAllowedPrice,
            maxAllowedPrice: maxAllowedPrice
        });
    }
}
