// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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

    function verify(bytes calldata payload, bytes calldata parameterPayload)
        external
        payable
        returns (bytes memory reportData_)
    {
        IVerifierFeeManager feeManager = s_feeManager;

        if (address(feeManager) != address(0)) {
            feeManager.processFee{ value: msg.value }(payload, parameterPayload, msg.sender);
        }

        (, reportData_) = abi.decode(payload, (bytes32[3], bytes));
    }

    receive() external payable { }
}
