// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";
import { IVerifierProxy } from "../../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";

contract MockFeeManager {
    function i_nativeAddress() external pure returns (address) {
        return address(0);
    }

    function getFeeAndReward(address, bytes calldata reportData, address)
        external
        pure
        returns (IFeeManager.Asset memory, IFeeManager.Asset memory, uint256)
    {
        IVerifierProxy.ReportV3 memory report = abi.decode(reportData, (IVerifierProxy.ReportV3));
        return (IFeeManager.Asset(address(0), report.nativeFee), IFeeManager.Asset(address(0), 0), 0);
    }
}
