// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.20;

contract ChainlinkDataSteamsLogEmitter {
    event PriceRequiredFor();

    function emitChainlinkDataStreamsEvent() public {
        emit PriceRequiredFor();
    }
}
