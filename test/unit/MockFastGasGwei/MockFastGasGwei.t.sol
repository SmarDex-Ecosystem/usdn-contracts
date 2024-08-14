// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { MockFastGasGwei } from "../../../src/OracleMiddleware/mock/MockFastGasGwei.sol";

/// @custom:feature Test functions in `MockFastGasGwei`
contract TestMockFastGasGwei is Test {
    MockFastGasGwei internal mock;

    /// @dev This value is randomly picked
    uint80 internal RANDOM_ROUND_ID = 2048;

    function setUp() external {
        mock = new MockFastGasGwei();
    }

    /**
     * @custom:scenario The `setRoundData` function
     * @custom:when The `setRoundData` function is called
     * @custom:then The roundData values should be updated
     */
    function test_gasMockSetRoundData() external {
        uint256 timestamp = block.timestamp;
        // a randomly picked value
        int256 newGasPrice = int256(99 gwei);

        MockFastGasGwei.RoundData memory data = MockFastGasGwei.RoundData({
            answer: newGasPrice,
            startedAt: timestamp,
            updatedAt: timestamp,
            answeredInRound: RANDOM_ROUND_ID
        });

        mock.setRoundData(RANDOM_ROUND_ID, data);
        mock.setLastRoundId(RANDOM_ROUND_ID);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mock.latestRoundData();

        assertEq(roundId, RANDOM_ROUND_ID, "RoundId should be updated");
        assertEq(answer, newGasPrice, "Answer should be equal new answer");
        assertEq(startedAt, timestamp, "The startedAt should be equal timestamp");
        assertEq(updatedAt, timestamp, "The updatedAt should be equal timestamp");
        assertEq(answeredInRound, RANDOM_ROUND_ID, "The answeredInRound should be updated");
        assertEq(mock.getLastRoundId(), RANDOM_ROUND_ID, "The last roundId should be updated");
    }

    /**
     * @custom:scenario The `deleteRoundData` function
     * @custom:when The `deleteRoundData` function is called
     * @custom:then The roundData values should be deleted
     */
    function test_gasMockDeleteRoundData() external {
        this.test_gasMockSetRoundData();

        mock.deleteRoundData(RANDOM_ROUND_ID);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mock.latestRoundData();

        assertEq(roundId, RANDOM_ROUND_ID, "Last roundId should be filled");
        assertEq(answer, 0, "Last answer should be equal 0");
        assertEq(startedAt, 0, "Last startedAt should be equal 0");
        assertEq(updatedAt, 0, "Last updatedAt should be equal 0");
        assertEq(answeredInRound, 0, "Last answeredInRound should be equal 0");
    }

    /**
     * @custom:scenario The `setRoundAnswer` function
     * @custom:when The `setRoundAnswer` function is called
     * @custom:then The answer value should be updated
     */
    function test_gasMockSetRoundAnswer() external {
        // a randomly picked value
        int256 newGasPrice = int256(44 gwei);

        this.test_gasMockSetRoundData();

        mock.setRoundAnswer(RANDOM_ROUND_ID, newGasPrice);

        (, int256 answer,,,) = mock.latestRoundData();

        assertEq(answer, newGasPrice, "Last answer should be updated");
    }

    /**
     * @custom:scenario The `setRoundTimestamp` function
     * @custom:when The `setRoundTimestamp` function is called
     * @custom:then The timestamp value should be updated
     */
    function test_gasMockSetRoundTimestamp() external {
        // a randomly picked value
        uint256 timestamp = 144;

        this.test_gasMockSetRoundData();

        mock.setRoundTimestamp(RANDOM_ROUND_ID, timestamp);

        (,, uint256 startedAt, uint256 updatedAt,) = mock.latestRoundData();

        assertEq(startedAt, timestamp, "Last answer should be updated");
        assertEq(updatedAt, timestamp, "Last answer should be updated");
    }

    /**
     * @custom:scenario The `getRoundData` function
     * @custom:when The `getRoundData` function is called
     * @custom:then The values should be as expected
     */
    function test_gasMockSetRoundId() external {
        // a randomly picked value
        uint256 timestamp = 144;

        this.test_gasMockSetRoundData();

        mock.setRoundTimestamp(RANDOM_ROUND_ID, timestamp);

        (,, uint256 startedAt, uint256 updatedAt,) = mock.getRoundData(RANDOM_ROUND_ID);

        assertEq(startedAt, timestamp, "Answer should be updated");
        assertEq(updatedAt, timestamp, "Answer should be updated");
    }

    /**
     * @custom:scenario The `pushAnswerInNewRound` function creates a new round
     * @custom:when The `pushAnswerInNewRound` function is called
     * @custom:then The last round ID is incremented
     * @custom:and The provided answer is set in the last round
     * @custom:and The timestamps are equal to block.timestamp
     */
    function test_pushAnswerInNewRound() external {
        uint256 lastRoundIdBefore = mock.getLastRoundId();
        (, int256 answerBefore,,,) = mock.latestRoundData();

        // skip one second to make sure the value of block.timestamp changes
        skip(1);

        mock.pushAnswerInNewRound(answerBefore + 1);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mock.latestRoundData();
        assertEq(mock.getLastRoundId(), lastRoundIdBefore + 1);
        assertEq(answeredInRound, roundId);
        assertEq(roundId, lastRoundIdBefore + 1);
        assertEq(answer, answerBefore + 1);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
    }
}
