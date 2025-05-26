// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IVerifierProxy } from "../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";

import { IMockFeeManager } from "./MockFeeManager.sol";

contract MockStreamVerifierProxy {
    IMockFeeManager public s_feeManager;

    constructor(address feeManagerAddress) {
        s_feeManager = IMockFeeManager(feeManagerAddress);
    }

    function setFeeManager(IMockFeeManager newFeeManager) external {
        s_feeManager = newFeeManager;
    }

    function verify(bytes calldata payload, bytes calldata) external payable returns (bytes memory reportData_) {
        IMockFeeManager feeManager = s_feeManager;

        (, reportData_) = abi.decode(payload, (bytes32[3], bytes));

        if (address(feeManager) != address(0)) {
            IVerifierProxy.ReportV3 memory report = abi.decode(reportData_, (IVerifierProxy.ReportV3));
            require(msg.value == report.nativeFee, "Wrong native fee");
        }
    }

    receive() external payable { }
}
