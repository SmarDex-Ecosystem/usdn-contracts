// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.20;

contract ChainlinkDataSteamsLogEmitter {
    event PriceRequiredFor(bytes data);

    function emitChainlinkDataStreamsEvent(bytes memory data) public {
        emit PriceRequiredFor(data);
    }
}
