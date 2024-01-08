// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title Chainlink Data Streams Log Emitter
 * @author Yashiru
 * @notice This contract is used to emit events for to trigger Chainlink Data Streams
 */
contract ChainlinkDataSteamsLogEmitter {
    /// @notice Event emitted to trigger Chainlink Data Streams
    event PriceRequiredFor(bytes data);

    /**
     * @notice Emit an event to trigger Chainlink Data Streams
     * @param data The data required to trigger the Chainlink Data Streams
     */
    function emitChainlinkDataStreamsEvent(bytes memory data) public {
        emit PriceRequiredFor(data);
    }
}
