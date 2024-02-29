// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/**
 * @title MockChainlinkOnChain contract
 * @dev This contract is used to test the OracleMiddleware contract.
 */
contract MockChainlinkOnChain {
    struct LatestRoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint80 answeredInRound;
    }

    bool private alwaysRevertOnCall;

    uint8 public decimals = 8;
    LatestRoundData private _latestRoundData;

    constructor() {
        _latestRoundData = LatestRoundData(0, int256(2000 * (10 ** decimals)), uint64(block.timestamp), 0);
    }

    /**
     * @notice Update manually the last publish time.
     * @param _lastPublishTime New last publish time.
     */
    function setLastPublishTime(uint256 _lastPublishTime) external {
        _latestRoundData.startedAt = uint64(_lastPublishTime);
    }

    function setLastPrice(int256 _lastPrice) external {
        _latestRoundData.answer = _lastPrice;
    }

    function setLatestRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint80 answeredInRound) external {
        _latestRoundData = LatestRoundData(roundId, answer, startedAt, answeredInRound);
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
        return (
            _latestRoundData.roundId,
            alwaysRevertOnCall ? int256(-1) : _latestRoundData.answer,
            _latestRoundData.startedAt, // for simplicity, we use the same timestamp for both startedAt and updatedAt
            _latestRoundData.startedAt,
            _latestRoundData.answeredInRound
        );
    }

    function latestTimestamp() external view returns (uint256) {
        return _latestRoundData.startedAt;
    }
}
