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
     * @custom:scenario Test the constructor
     * @custom:when The contract is deployed
     * @custom:then The initial data should be set
     */
    function test_gasMockConstructor() external view {
        assertEq(mock.owner(), address(this), "Owner should be this address");

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mock.latestRoundData();

        assertEq(roundId, 0, "Last roundId should be 0");
        assertGt(answer, 0, "Last answer should be greater than 0");
        assertEq(startedAt, block.timestamp, "Last startedAt should be greater than 0");
        assertEq(updatedAt, block.timestamp, "Last updatedAt should be greater than 0");
        assertEq(answeredInRound, 0, "Last answeredInRound should be equal 0");
    }

    /**
     * @custom:scenario The `decimals` function
     * @custom:when The `decimals` function is called
     * @custom:then The value returned should be 0
     */
    function test_gasMockDecimals() external view {
        assertEq(mock.decimals(), 0, "Decimals should be 0");
    }

    /**
     * @custom:scenario The `description` function
     * @custom:when The `description` function is called
     * @custom:then The value returned should be equal to the expected value
     */
    function test_gasMockDescription() external view {
        assertFalse(
            keccak256(abi.encodePacked(mock.description())) == keccak256(abi.encodePacked("")),
            "Description should be filled"
        );
    }

    /**
     * @custom:scenario The `version` function
     * @custom:when The `version` function is called
     * @custom:then The value returned should be equal to the expected value
     */
    function test_gasMockVersion() external view {
        assertGt(mock.version(), 0, "Version should be greater than 0");
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
}
