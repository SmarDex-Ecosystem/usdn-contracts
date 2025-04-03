// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PostconditionsAdmin } from "./helper/postconditions/PostconditionsAdmin.sol";
import { PreconditionsAdmin } from "./helper/preconditions/PreconditionsAdmin.sol";

contract FuzzAdmin is PreconditionsAdmin, PostconditionsAdmin {
    function fuzz_setPrice(int256 priceChangePercent) public {
        SetPricePreconditions memory params = setPricePreconditions(priceChangePercent);

        int256 newPriceUSD = params.newPrice;

        setChainlinkPrice(newPriceUSD);
        setPythPrice(newPriceUSD);
    }

    function setChainlinkPrice(int256 priceUSD) internal {
        int256 scaledPrice = priceUSD * int256(10 ** chainlink.decimals());
        chainlink.setLastPrice(scaledPrice);
        chainlink.setLastPublishTime(block.timestamp);

        uint80 roundId = 1;
        uint256 startedAt = block.timestamp;
        uint80 answeredInRound = 1;

        chainlink.setLatestRoundData(roundId, scaledPrice, startedAt, answeredInRound);
    }

    function setPythPrice(int256 priceUSD) internal {
        pyth.setLastPublishTime(block.timestamp + wstEthOracleMiddleware.getValidationDelay());
        pyth.setPrice(int64(priceUSD * int64(uint64(10 ** chainlink.decimals()))));
        pyth.setConf(0); //NOTE: confidence hardcoded to 0
    }

    function pumpPrice(uint256 loops) internal {
        loops = loops > 20 ? 20 : loops;
        for (uint256 i; i < loops; ++i) {
            fuzz_setPrice((type(int256).max / 5));
        }
    }

    //will not dump below 1500 in a default anti liquidation mode
    function crashPrice(uint256 loops) internal {
        loops = loops > 20 ? 20 : loops;
        for (uint256 i; i < loops; ++i) {
            fuzz_setPrice(-10_000);
        }
    }
}
