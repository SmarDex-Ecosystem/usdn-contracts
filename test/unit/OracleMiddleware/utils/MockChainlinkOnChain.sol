// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/**
 * @title MockChainlinkOnChain contract
 * @dev This contract is used to test the OracleMiddleware contract.
 */
contract MockChainlinkOnChain {
    bool private alwaysRevertOnCall;

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

    /**
     * @notice Toggle the revert on call.
     */
    function toggleRevert() external {
        alwaysRevertOnCall = !alwaysRevertOnCall;
    }

    /**
     * @notice Get the last publish time.
     * @return roundId The round id.
     * @return answer The actual asset price.
     * @return startedAt The timestamp when the round was started.
     * @return updatedAt The timestamp when the round was updated.
     * @return answeredInRound the round ID of the round in which the answer was computed.
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, alwaysRevertOnCall ? int256(-1) : int256(2000 * 1e8), 0, lastPublishTime, 0);
    }

    /**
     * @notice Get the decimals of the price asset.
     */
    function decimals() external pure returns (uint8) {
        return 8;
    }
}
