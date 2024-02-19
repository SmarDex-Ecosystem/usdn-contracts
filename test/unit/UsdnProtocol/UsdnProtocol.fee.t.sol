// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

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
     * @custom:scenario Check that setFeeBps() reverts when the value is too big
     * @custom:given The fee value is > BPS_DIVISOR
     * @custom:then The protocol reverts with `UsdnProtocolInvalidProtocolFeeBps`
     */
    function test_RevertWhen_setFeeBps_tooBig() public {
        uint16 bpsDivisor = uint16(protocol.BPS_DIVISOR());
        vm.startPrank(ADMIN);
        vm.expectRevert(UsdnProtocolInvalidProtocolFeeBps.selector);
        protocol.setFeeBps(bpsDivisor + 1);
        vm.stopPrank();
    }

    /**
     * @custom:scenario Check setFeeBps() function
     * @custom:given The fee bps is 0
     * @custom:then The protocol emits `FeeBpsUpdated` event with 0
     * @custom:and Pending protocol fee is 0 after action
     */
    function test_setFeeBps() public AdminPrank {
        wstETH.mintAndApprove(ADMIN, 1000 ether, address(protocol), 1000 ether);

        vm.expectEmit();
        emit FeeBpsUpdated(0);
        protocol.setFeeBps(0);

        protocol.initiateDeposit(1000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
    }

    /**
     * @custom:scenario Check that setFeeCollector() reverts when the value is address(0)
     * @custom:given The feeCollector is address(0)
     * @custom:then The protocol reverts with `UsdnProtocolInvalidFeeCollector`
     */
    function test_RevertWhen_setFeeCollector_addressZero() public AdminPrank {
        vm.expectRevert(UsdnProtocolInvalidFeeCollector.selector);
        protocol.setFeeCollector(address(0));
    }

    /**
     * @custom:scenario Check setFeeCollector() function
     * @custom:given The feeCollector is address(this)
     * @custom:then The protocol emits `FeeCollectorUpdated` event with address(this)
     * @custom:and The _feeCollector is address(this)
     */
    function test_setFeeCollector() public AdminPrank {
        vm.expectEmit();
        emit FeeCollectorUpdated(address(this));
        protocol.setFeeCollector(address(this));
        assertEq(protocol.feeCollector(), address(this));
    }

    /**
     * @custom:scenario Check setFeeThreshold() function
     * @custom:given The feeThreshold value is 5 ether
     * @custom:then The protocol emits `FeeThresholdUpdated` event with address(this)
     * @custom:and The _feeThreshold is 5 ether
     */
    function test_setFeeThreshold() public AdminPrank {
        vm.expectEmit();
        emit FeeThresholdUpdated(5 ether);
        protocol.setFeeThreshold(5 ether);
        assertEq(protocol.feeThreshold(), 5 ether);
    }

    /**
     * @custom:scenario Check that the pending protocol fee is updated after an action
     * @custom:given The pending protocol fee is 0
     * @custom:then A deposit of 10_000 wstETH
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
    function test_feeHitThreshold() public {
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
        assertGe(wstETH.balanceOf(ADMIN), protocol.feeThreshold(), "fee collector balance after collect");
    }
}
