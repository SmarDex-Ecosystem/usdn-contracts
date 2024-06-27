// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature All fees functionality of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolFee is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        params.flags.enableProtocolFees = true;
        super._setUp(params);
    }

    /**
     * @custom:scenario Check that setProtocolFeeBps() reverts when the value is too big
     * @custom:given The fee value is > BPS_DIVISOR
     * @custom:then The protocol reverts with `UsdnProtocolInvalidProtocolFeeBps`
     */
    function test_RevertWhen_setFeeBps_tooBig() public adminPrank {
        uint16 bpsDivisor = uint16(protocol.BPS_DIVISOR());
        vm.expectRevert(UsdnProtocolInvalidProtocolFeeBps.selector);
        protocol.setProtocolFeeBps(bpsDivisor + 1);
    }

    /**
     * @custom:scenario Check setProtocolFeeBps() function
     * @custom:given The fee bps is 0
     * @custom:then The protocol emits `FeeBpsUpdated` event with 0
     * @custom:and Pending protocol fee is 0 after action
     */
    function test_setFeeBps() public adminPrank {
        wstETH.mintAndApprove(ADMIN, 1000 ether, address(protocol), 1000 ether);

        vm.expectEmit();
        emit FeeBpsUpdated(0);
        protocol.setProtocolFeeBps(0);

        _waitBeforeLiquidation();
        protocol.testLiquidate(abi.encode(DEFAULT_PARAMS.initialPrice), 0);

        assertEq(protocol.getPendingProtocolFee(), 0, "initial pending protocol fee");
    }

    /**
     * @custom:scenario Check that setFeeCollector() reverts when the value is address(0)
     * @custom:given The feeCollector is address(0)
     * @custom:then The protocol reverts with `UsdnProtocolInvalidFeeCollector`
     */
    function test_RevertWhen_setFeeCollector_addressZero() public adminPrank {
        vm.expectRevert(UsdnProtocolInvalidFeeCollector.selector);
        protocol.setFeeCollector(address(0));
    }

    /**
     * @custom:scenario Check setFeeCollector() function
     * @custom:given The feeCollector is address(this)
     * @custom:then The protocol emits `FeeCollectorUpdated` event with address(this)
     * @custom:and The _feeCollector is address(this)
     */
    function test_setFeeCollector() public adminPrank {
        vm.expectEmit();
        emit FeeCollectorUpdated(address(this));
        protocol.setFeeCollector(address(this));
        assertEq(protocol.getFeeCollector(), address(this));
    }

    /**
     * @custom:scenario Check setFeeThreshold() function
     * @custom:given The feeThreshold value is 5 ether
     * @custom:then The protocol emits `FeeThresholdUpdated` event with address(this)
     * @custom:and The _feeThreshold is 5 ether
     */
    function test_setFeeThreshold() public adminPrank {
        vm.expectEmit();
        emit FeeThresholdUpdated(5 ether);
        protocol.setFeeThreshold(5 ether);
        assertEq(protocol.getFeeThreshold(), 5 ether);
    }

    /**
     * @custom:scenario Check that the pending protocol fee is updated after an action
     * @custom:given The pending protocol fee is 0
     * @custom:then A deposit of 10_000 wstETH
     * @custom:and A validation of the deposit
     * @custom:then The pending protocol fee is > 0
     */
    function test_pendingProtocolFee() public {
        assertEq(protocol.getPendingProtocolFee(), 0, "initial pending protocol fee");
        setUpUserPositionInVault(
            address(this), ProtocolAction.ValidateDeposit, 10_000 ether, DEFAULT_PARAMS.initialPrice
        );
        assertGt(protocol.getPendingProtocolFee(), 0, "pending protocol fee after deposit");
    }

    /**
     * @custom:scenario Check that the pending protocol fee is distributed to the fee collector
     * after the threshold is reached
     * @custom:given The pending protocol fee is 0
     * @custom:and Multiple actions are performed to reach the fee threshold
     * @custom:then The pending protocol fee is distributed to the fee collector
     */
    function test_feeHitThreshold() public {
        setUpUserPositionInVault(
            address(this), ProtocolAction.ValidateDeposit, 10_000 ether, DEFAULT_PARAMS.initialPrice
        );
        skip(2 days);

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5000 ether,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 2,
                price: DEFAULT_PARAMS.initialPrice
            })
        );
        skip(8 days);
        assertEq(wstETH.balanceOf(address(feeCollector)), 0, "fee collector balance before collect");
        setUpUserPositionInVault(
            address(this), ProtocolAction.InitiateDeposit, 10_000 ether, DEFAULT_PARAMS.initialPrice
        );
        assertGe(
            wstETH.balanceOf(address(feeCollector)), protocol.getFeeThreshold(), "fee collector balance after collect"
        );
    }
}
