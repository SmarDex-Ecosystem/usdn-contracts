// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";

import { IMockFeeManager } from "../../utils/MockFeeManager.sol";

/// @custom:feature The `_getChainlinkDataStreamFeeData` function of the `ChainlinkDataStreamsOracle`.
contract TestOracleMiddlewareWithDataStreamFeeData is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamFeeData` function.
     * @custom:when The function is called.
     * @custom:then The `feeData.assetAddress` should match the native address of the fee manager.
     * @custom:and The `feeData.amount` should be equal to the `report.nativeFee`.
     */
    function test_getChainlinkDataStreamFeeData() public view {
        IFeeManager.Asset memory feeData = oracleMiddleware.i_getChainlinkDataStreamFeeData(payload);

        assertEq(feeData.assetAddress, mockFeeManager.i_nativeAddress(), "Wrong fee native address");
        assertEq(feeData.amount, report.nativeFee, "Wrong fee amount");
    }

    /**
     * @custom:scenario Tests the `_getChainlinkDataStreamFeeData` function with an empty fee manager.
     * @custom:when The function is called with an empty fee manager.
     * @custom:then The fee data must be empty.
     */
    function test_getChainlinkDataStreamFeeDataWithoutFeeManager() public {
        IMockFeeManager emptyFeeManager = IMockFeeManager(address(0));
        mockStreamVerifierProxy.setFeeManager(emptyFeeManager);
        IFeeManager.Asset memory feeData = oracleMiddleware.i_getChainlinkDataStreamFeeData(payload);

        assertEq(feeData.assetAddress, address(emptyFeeManager), "Wrong fee native address");
        assertEq(feeData.amount, 0, "Wrong fee amount");
    }
}
