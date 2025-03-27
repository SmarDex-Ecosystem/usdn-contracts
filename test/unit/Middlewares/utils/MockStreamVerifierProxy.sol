// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IVerifierProxy } from "../../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";

interface IVerifierFeeManager {
    function processFee(bytes calldata payload, bytes calldata parameterPayload, address subscriber) external payable;
}

contract MockStreamVerifierProxy {
    IVerifierFeeManager public s_feeManager;

    constructor(address feeManagerAddress) {
        s_feeManager = IVerifierFeeManager(feeManagerAddress);
    }

    function setFeeManager(IVerifierFeeManager newFeeManager) external {
        s_feeManager = newFeeManager;
    }

    function verify(bytes calldata payload, bytes calldata) external payable returns (bytes memory reportData_) {
        IVerifierFeeManager feeManager = s_feeManager;

        (, reportData_) = abi.decode(payload, (bytes32[3], bytes));

        if (address(feeManager) != address(0)) {
            IVerifierProxy.ReportV3 memory report = abi.decode(reportData_, (IVerifierProxy.ReportV3));
            require(msg.value == report.nativeFee, "Wrong native fee");
        }
    }

    receive() external payable { }
}
