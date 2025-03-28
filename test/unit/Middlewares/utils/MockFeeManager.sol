// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";
import { IVerifierProxy } from "../../../../../src/interfaces/OracleMiddleware/IVerifierProxy.sol";

contract MockFeeManager {
    address internal constant NATIVE_ADDRESS = address(1);

    function i_nativeAddress() external pure returns (address) {
        return NATIVE_ADDRESS;
    }

    function getFeeAndReward(address, bytes calldata reportData, address)
        external
        pure
        returns (IFeeManager.Asset memory feeData_, IFeeManager.Asset memory rewardData_, uint256 discount_)
    {
        IVerifierProxy.ReportV3 memory report = abi.decode(reportData, (IVerifierProxy.ReportV3));
        feeData_ = IFeeManager.Asset({ amount: report.nativeFee, assetAddress: NATIVE_ADDRESS });
        return (feeData_, rewardData_, discount_);
    }
}
