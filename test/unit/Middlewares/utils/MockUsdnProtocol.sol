// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

contract MockUsdnProtocol {
    uint128 internal _lowLatencyValidatorDeadline;

    function getLowLatencyValidatorDeadline() external view returns (uint128) {
        return _lowLatencyValidatorDeadline;
    }

    function setLowLatencyValidatorDeadline(uint128 lowLatencyValidatorDeadline) external {
        _lowLatencyValidatorDeadline = lowLatencyValidatorDeadline;
    }
}
