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

    function test_setFeeBps() public {
        wstETH.mintAndApprove(ADMIN, 1000 ether, address(protocol), 1000 ether);
        uint16 bpsDivisor = uint16(protocol.BPS_DIVISOR());

        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidProtocolFeeBps.selector, bpsDivisor + 1));
        protocol.setFeeBps(bpsDivisor + 1);
        protocol.setFeeBps(0);
        protocol.initiateDeposit(1000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
        vm.stopPrank();
    }

    function test_setFeeCollector() public {
        vm.startPrank(ADMIN);
        vm.expectRevert(UsdnProtocolInvalidFeeCollector.selector);
        protocol.setFeeCollector(address(0));
        protocol.setFeeCollector(address(this));
        vm.stopPrank();
        assertEq(protocol.feeCollector(), address(this));
    }

    function test_pendingProtocolFee() public {
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), 100_000 ether);

        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
        protocol.initiateDeposit(10_000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertGt(protocol.pendingProtocolFee(), 0, "pending protocol fee after deposit");
    }

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
