// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/// @custom:feature The `_checkPendingFee` function
contract TestUsdnProtocolCheckPendingFee is UsdnProtocolBaseFixture {
    uint256 limit;
    address feeCollectorAddr;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        limit = protocol.getFeeThreshold();
        feeCollectorAddr = protocol.getFeeCollector();
    }

    /**
     * @custom:scenario Fee is exactly at the limit
     * @custom:given The pending fee is exactly equal to the limit
     * @custom:when The `_checkPendingFee` function is called
     * @custom:then The pending fee is transferred to the fee collector
     * @custom:and The pending fee is reset to zero
     * @custom:and The correct event is emitted
     */
    function test_checkPendingFee() public {
        protocol.setPendingProtocolFee(limit);
        uint256 balanceBefore = wstETH.balanceOf(feeCollectorAddr);

        vm.expectEmit();
        emit ProtocolFeeDistributed(feeCollectorAddr, limit);
        protocol.i_checkPendingFee();

        assertEq(wstETH.balanceOf(feeCollectorAddr), balanceBefore + limit, "fee collector balance");
        assertEq(protocol.getPendingProtocolFee(), 0, "pending fee");
    }

    /**
     * @custom:scenario Fee is below the limit
     * @custom:given The pending fee is below the limit
     * @custom:when The `_checkPendingFee` function is called
     * @custom:then The pending fee is not transferred to the fee collector
     * @custom:and The pending fee is not reset to zero
     * @custom:and No events are emitted
     */
    function test_checkPendingFeeBelowLimit() public {
        protocol.setPendingProtocolFee(limit - 1);
        uint256 balanceBefore = wstETH.balanceOf(feeCollectorAddr);

        vm.recordLogs();
        protocol.i_checkPendingFee();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "logs length");

        assertEq(wstETH.balanceOf(feeCollectorAddr), balanceBefore, "fee collector balance");
        assertEq(protocol.getPendingProtocolFee(), limit - 1, "pending fee");
    }
}
