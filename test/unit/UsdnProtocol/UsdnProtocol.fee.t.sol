// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature All fees functionality of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolFee is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check setFeeBps() function
     * @custom:given The first value is > BPS_DIVISOR
     * @custom:then The protocol reverts with `UsdnProtocolInvalidProtocolFeeBps`
     * @custom:and The second value is 0
     * @custom:then The protocol emits `FeeBpsUpdated` event with 0
     * @custom:and Pending protocol fee is 0 after action
     */
    function test_setFeeBps() public {
        wstETH.mintAndApprove(ADMIN, 1000 ether, address(protocol), 1000 ether);
        uint16 bpsDivisor = uint16(protocol.BPS_DIVISOR());

        vm.startPrank(ADMIN);
        vm.expectRevert(UsdnProtocolInvalidProtocolFeeBps.selector);
        protocol.setFeeBps(bpsDivisor + 1);

        vm.expectEmit();
        emit FeeBpsUpdated(0);
        protocol.setFeeBps(0);

        protocol.initiateDeposit(1000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
        vm.stopPrank();
    }

    /**
     * @custom:scenario Check setFeeCollector() function
     * @custom:given The first value is address(0)
     * @custom:then The protocol reverts with `UsdnProtocolInvalidFeeCollector`
     * @custom:and The second value is address(this)
     * @custom:then The protocol emits `FeeCollectorUpdated` event with address(this)
     */
    function test_setFeeCollector() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(UsdnProtocolInvalidFeeCollector.selector);
        protocol.setFeeCollector(address(0));

        vm.expectEmit();
        emit FeeCollectorUpdated(address(this));
        protocol.setFeeCollector(address(this));
        vm.stopPrank();
        assertEq(protocol.feeCollector(), address(this));
    }

    /**
     * @custom:scenario Check setFeeThreshold() function
     * @custom:given The first value is 0
     * @custom:then The protocol reverts with `UsdnProtocolInvalidFeeThreshold`
     * @custom:and The second value is 5 ether
     * @custom:then The protocol emits `FeeThresholdUpdated` event with address(this)
     */
    function test_setFeeThreshold() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(UsdnProtocolInvalidFeeThreshold.selector);
        protocol.setFeeThreshold(0);

        vm.expectEmit();
        emit FeeThresholdUpdated(5 ether);
        protocol.setFeeThreshold(5 ether);
        vm.stopPrank();
        assertEq(protocol.feeThreshold(), 5 ether);
    }

    /**
     * @custom:scenario Check that the pending protocol fee is updated after an action
     * @custom:given The pending protocol fee is 0
     * @custom:then A deposit of 100_000 wstETH
     * @custom:and A validation of the deposit
     * @custom:then The pending protocol fee is > 0
     */
    function test_pendingProtocolFee() public {
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), 100_000 ether);

        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
        protocol.initiateDeposit(10_000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertGt(protocol.pendingProtocolFee(), 0, "pending protocol fee after deposit");
    }

    /**
     * @custom:scenario Check that the pending protocol fee is distributed to the fee collector
     * after the threshold is reached
     * @custom:given The pending protocol fee is 0
     * @custom:and Multiple actions are performed to reach the fee threshold
     * @custom:then The pending protocol fee is distributed to the fee collector
     */
    function test_feeHitThreshhold() public {
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), 100_000 ether);

        protocol.initiateDeposit(10_000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        skip(4 days);
        protocol.initiateOpenPosition(
            5000 ether, DEFAULT_PARAMS.initialPrice / 2, abi.encode(DEFAULT_PARAMS.initialPrice), ""
        );
        protocol.validateOpenPosition(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        skip(8 days);
        assertEq(wstETH.balanceOf(ADMIN), 0, "fee collector balance before collect");
        protocol.initiateDeposit(10_000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertGt(wstETH.balanceOf(ADMIN), 0, "fee collector balance after collect");
    }
}
