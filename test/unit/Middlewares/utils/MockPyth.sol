// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { PythErrors } from "@pythnetwork/pyth-sdk-solidity/PythErrors.sol";

import { ETH_PRICE, ETH_CONF } from "test/unit/Middlewares/utils/Constants.sol";

/**
 * @title MockPythError interface
 * @dev This interface is used to define the revert reason of the MockPyth contract.
 */
interface IMockPythError {
    error MockedPythError();
}

/**
 * @title MockPyth contract
 * @dev This contract is used to test the OracleMiddleware contract.
 * The original coed can be found here:
 * https://github.com/pyth-network/pyth-crosschain/blob/main/target_chains/ethereum/contracts/contracts/pyth/Pyth.sol
 */
contract MockPyth is IMockPythError {
    bool private alwaysRevertOnCall;

    uint64 public lastPublishTime;
    int64 public price = int64(uint64(ETH_PRICE));
    uint64 public conf = uint64(ETH_CONF);
    int32 public expo = -8;

    constructor() {
        lastPublishTime = uint64(block.timestamp);
    }

    /**
     * @notice Update manually the last publish time.
     * @param _lastPublishTime New last publish time.
     */
    function setLastPublishTime(uint256 _lastPublishTime) external {
        lastPublishTime = uint64(_lastPublishTime);
    }

    /**
     * @notice Update manually the price.
     * @param _price New price.
     */
    function setPrice(int64 _price) external {
        price = _price;
    }

    /**
     * @notice Update manually the confidence interval.
     * @param _conf New confidence interval
     */
    function setConf(uint64 _conf) external {
        conf = _conf;
    }

    /**
     * @notice Update manually the exponent.
     * @param _expo New exponent
     */
    function setExpo(int32 _expo) external {
        expo = _expo;
    }

    /**
     * @notice Toggle the revert on call.
     */
    function toggleRevert() external {
        alwaysRevertOnCall = !alwaysRevertOnCall;
    }

    /// @notice Mock of the real parsePriceFeedUpdatesUnique function.
    /// @param priceIds Array of price ids.
    /// @param minPublishTime minimum acceptable publishTime for the given `priceIds`.
    /// @return priceFeeds Array of the price feeds corresponding to the given `priceIds` (with the same order).
    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds) {
        return parsePriceFeedUpdatesUnique(updateData, priceIds, minPublishTime, maxPublishTime);
    }

    /// @notice Mock of the real parsePriceFeedUpdatesUnique function.
    /// @param priceIds Array of price ids.
    /// @param minPublishTime minimum acceptable publishTime for the given `priceIds`.
    /// @return priceFeeds Array of the price feeds corresponding to the given `priceIds` (with the same order).
    function parsePriceFeedUpdatesUnique(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64
    ) public payable returns (PythStructs.PriceFeed[] memory priceFeeds) {
        if (alwaysRevertOnCall) revert MockedPythError();

        uint256 requiredFee = getUpdateFee(updateData);
        if (msg.value < requiredFee) revert PythErrors.InsufficientFee();

        lastPublishTime = minPublishTime;

        priceFeeds = new PythStructs.PriceFeed[](priceIds.length);
        PythStructs.Price memory _price =
            PythStructs.Price({ price: price, conf: conf, expo: expo, publishTime: lastPublishTime });

        for (uint256 i; i < priceIds.length;) {
            priceFeeds[i] = PythStructs.PriceFeed({ id: bytes32(priceIds[i]), price: _price, emaPrice: _price });

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Mock of the real parsePriceFeedUpdatesUnique function.
    /// @return price The fee to update the price.
    function getUpdateFee(bytes[] calldata updateData) public pure returns (uint256) {
        return 1 wei * updateData.length;
    }

    /// @dev Simulate an invalid price so that the cached price is never used in testing
    function getPriceUnsafe(bytes32) public pure returns (PythStructs.Price memory price_) {
        price_.price = -1;
    }
}
