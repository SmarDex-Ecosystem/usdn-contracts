// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

contract MockInvalidOracleMiddleware {
    uint16 internal _lowLatencyDelay;

    function getLowLatencyDelay() external view returns (uint16) {
        return _lowLatencyDelay;
    }

    function setLowLatencyDelay(uint16 newLowLatencyDelay) external {
        _lowLatencyDelay = newLowLatencyDelay;
    }
}
