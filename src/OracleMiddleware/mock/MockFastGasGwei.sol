// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice This contract is used to set the gas price manually
contract MockFastGasGwei is Ownable, AggregatorV3Interface {
    /**
     * @notice The RoundData struct
     * @param answer The roundId answer value
     * @param startedAt The roundId startedAt value
     * @param updatedAt The roundId updatedAt value
     * @param answeredInRound The roundId answeredInRound value
     */
    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    /// @notice The last roundId
    uint80 internal lastRoundId;

    /// @notice The roundData by roundId
    mapping(uint80 => RoundData) internal roundData;

    constructor() Ownable(msg.sender) {
        roundData[0] = RoundData({
            answer: int256(11 gwei),
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 0
        });
    }

    /**
     * @notice Returns the oracle decimals
     * @return The decimals value
     */
    function decimals() external pure returns (uint8) {
        return 0;
    }

    /**
     * @notice Returns the oracle description
     * @return The description value
     */
    function description() external pure returns (string memory) {
        return "Fast Gas / Gwei";
    }

    /**
     * @notice Returns the oracle version
     * @return The version value
     */
    function version() external pure returns (uint256) {
        return 4;
    }

    /**
     * @notice Returns the roundData of the roundId
     * @param roundId The roundId value
     */
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
    {
        return _parseRoundData(roundId);
    }

    /// @notice Returns the last roundId
    function getLastRoundId() external view returns (uint80) {
        return lastRoundId;
    }

    /**
     * @notice Returns the last roundData values
     * @return roundId_ The roundId value
     * @return answer_ The answer value
     * @return startedAt_ The startedAt value
     * @return updatedAt_ The updatedAt value
     * @return answeredInRound_ The answeredInRound value
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
    {
        return _parseRoundData(lastRoundId);
    }

    /**
     * @notice Increment the lastRoundId and set its data
     * @param gasPrice The price of the gas for the new round
     */
    function pushAnswerInNewRound(int256 gasPrice) external onlyOwner {
        ++lastRoundId;
        roundData[lastRoundId] = RoundData({
            answeredInRound: lastRoundId,
            answer: gasPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp
        });
    }

    /**
     * @notice Set the data of the roundId
     * @param roundId The roundId value
     * @param data The roundId data
     */
    function setRoundData(uint80 roundId, RoundData memory data) external onlyOwner {
        roundData[roundId] = data;
    }

    /**
     * @notice Delete the data of the roundId
     * @param roundId The roundId value
     */
    function deleteRoundData(uint80 roundId) external onlyOwner {
        delete roundData[roundId];
    }

    /**
     * @notice Set the answer of the roundId
     * @param roundId The roundId value
     * @param answer The answer value
     */
    function setRoundAnswer(uint80 roundId, int256 answer) external onlyOwner {
        roundData[roundId].answer = answer;
    }

    /**
     * @notice Set the timestamp of the roundId
     * @param roundId The roundId value
     * @param timestamp The timestamp value
     */
    function setRoundTimestamp(uint80 roundId, uint256 timestamp) external onlyOwner {
        roundData[roundId].startedAt = timestamp;
        roundData[roundId].updatedAt = timestamp;
    }

    /**
     * @notice Set the last roundId
     * @param roundId The roundId value
     */
    function setLastRoundId(uint80 roundId) external onlyOwner {
        lastRoundId = roundId;
    }

    /**
     * @notice Parse the roundId data
     * @param roundId The roundId value
     * @return roundId_ The roundId value
     * @return answer_ The answer value
     * @return startedAt_ The startedAt value
     * @return updatedAt_ The updatedAt value
     * @return answeredInRound_ The answeredInRound value
     */
    function _parseRoundData(uint80 roundId)
        internal
        view
        returns (uint80 roundId_, int256 answer_, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_)
    {
        roundId_ = roundId;

        RoundData memory data = roundData[roundId];

        answer_ = data.answer;
        startedAt_ = data.startedAt;
        updatedAt_ = data.updatedAt;
        answeredInRound_ = data.answeredInRound;
    }
}
