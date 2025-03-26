// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";
import { IVerifierFeeManager } from "../../utils/MockStreamVerifierProxy.sol";

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";

/// @custom:feature The `_getChainlinkDataStreamFeeData` function of the `ChainlinkDataStreamsOracle`.
contract TestOracleMiddlewareWithDataStreamFeeData is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `getChainlinkDataStreamFeeData` function.
     * @custom:when The function is called.
     * @custom:then The fee data assetAddress equal to weth address.
     * @custom:and The fee data amount equal to report nativeFee.
     */
    function test_getChainlinkDataStreamFeeData() public view {
        IFeeManager.Asset memory feeData = oracleMiddleware.i_getChainlinkDataStreamFeeData(payload);

        assertEq(feeData.assetAddress, wethTargetAddress, "Wrong fee native address");
        assertEq(feeData.amount, report.nativeFee, "Wrong fee amount");
    }

    /**
     * @custom:scenario Tests the `getChainlinkDataStreamFeeData` function without a fee manager.
     * @custom:when The function is called.
     * @custom:then The fee data must be empty.
     */
    function test_getChainlinkDataStreamFeeDataWithoutFeeManager() public {
        mockStreamVerifierProxy.setFeeManager(IVerifierFeeManager(address(0)));
        IFeeManager.Asset memory feeData = oracleMiddleware.i_getChainlinkDataStreamFeeData(payload);

        assertEq(feeData.assetAddress, address(0), "Wrong fee native address");
        assertEq(feeData.amount, 0, "Wrong fee amount");
    }
}
