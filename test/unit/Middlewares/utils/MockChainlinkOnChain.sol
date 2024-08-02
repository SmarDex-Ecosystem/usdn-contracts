// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/**
 * @title MockChainlinkOnChain contract
 * @dev This contract is used to test the OracleMiddleware contract
 */
contract MockChainlinkOnChain {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    bool private alwaysRevertOnCall;

    uint8 public decimals = 8;
    RoundData private _latestRoundData;

    mapping(uint80 => RoundData) _roundData;

    constructor() {
        _latestRoundData = RoundData(0, int256(2000 * 10 ** decimals), uint64(block.timestamp), 0, 0);
        _roundData[0] = RoundData(0, int256(2000 * 10 ** decimals), uint64(block.timestamp), uint64(block.timestamp), 0);
        _roundData[1] =
            RoundData(0, int256(2000 * 10 ** decimals), uint64(block.timestamp + 1), uint64(block.timestamp + 1), 0);
    }

    /**
     * @notice Update manually the last publish time
     * @param _lastPublishTime New last publish time
     */
    function setLastPublishTime(uint256 _lastPublishTime) external {
        _latestRoundData.startedAt = uint64(_lastPublishTime);
    }

    function setLastPrice(int256 _lastPrice) external {
        _latestRoundData.answer = _lastPrice;
    }

    function setLatestRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint80 answeredInRound) external {
        _latestRoundData = RoundData(roundId, answer, startedAt, 0, answeredInRound);
    }

    /**
     * @notice Update manually the roundId publish time
     * @param roundId The price round id
     * @param timestamp The price timestamp
     */
    function setRoundTimestamp(uint80 roundId, uint256 timestamp) external {
        _roundData[roundId].updatedAt = timestamp;
    }

    /**
     * @notice Update manually the roundId price
     * @param roundId The round id
     * @param price The price
     */
    function setRoundPrice(uint80 roundId, int256 price) external {
        _roundData[roundId].answer = price;
    }

    function setRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint256 updateAt, uint80 answeredInRound)
        external
    {
        _roundData[roundId] = RoundData(roundId, answer, startedAt, updateAt, answeredInRound);
    }

    /**
     * @notice Toggle the revert on call
     */
    function toggleRevert() external {
        alwaysRevertOnCall = !alwaysRevertOnCall;
    }

    /**
     * @notice Get the last publish time
     * @return roundId_ The round id
     * @return answer_ The actual asset price
     * @return startedAt_ The timestamp when the round was started
     * @return updatedAt_ The timestamp when the round was updated
     * @return answeredInRound_ the round ID of the round in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
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

    /**
     * @notice Get the round data by roundId
     * @param roundId The round id
     * @return roundId_ The round id
     * @return answer_ The actual asset price
     * @return startedAt_ The timestamp when the round was started
     * @return updatedAt_ The timestamp when the round was updated
     * @return answeredInRound_ the round ID of the round in which the answer was computed
     */
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
    {
        return (
            _roundData[roundId].roundId,
            alwaysRevertOnCall ? int256(-1) : _roundData[roundId].answer,
            _roundData[roundId].startedAt,
            _roundData[roundId].updatedAt,
            _roundData[roundId].answeredInRound
        );
    }
}
