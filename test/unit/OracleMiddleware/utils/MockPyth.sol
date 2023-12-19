// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title MockPyth contract
 * @dev This contract is used to test the OracleMiddleware contract.
 */
contract MockPyth {
    uint64 public lastPublishTime;

    constructor() {
        lastPublishTime = uint64(block.timestamp);
    }

    /**
     * @notice Update manually the last publish time.
     * @param _lastPublishTime New last publish time.
     */
    function updateLastPublishTime(uint256 _lastPublishTime) external {
        lastPublishTime = uint64(_lastPublishTime);
    }

    /// @notice Mock of the real parsePriceFeedUpdatesUnique function.
    /// @param updateData Array of price update data.
    /// @param priceIds Array of price ids.
    /// @param minPublishTime minimum acceptable publishTime for the given `priceIds`.
    /// @param maxPublishTime maximum acceptable publishTime for the given `priceIds`.
    /// @return priceFeeds Array of the price feeds corresponding to the given `priceIds` (with the same order).
    function parsePriceFeedUpdatesUnique(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds) {
        lastPublishTime = minPublishTime;

        priceFeeds = new PythStructs.PriceFeed[](priceIds.length);
        PythStructs.Price memory price =
            PythStructs.Price({ price: 2000 gwei, conf: 20 gwei, expo: 8, publishTime: lastPublishTime });

        for (uint256 i; i < priceIds.length;) {
            priceFeeds[i] = PythStructs.PriceFeed({ id: bytes32(priceIds[i]), price: price, emaPrice: price });

            unchecked {
                ++i;
            }
        }
    }
}
