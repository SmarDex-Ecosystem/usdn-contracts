// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

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
        wstETH.mint(address(this), 1000 ether);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    function test_setFeeBps() public {
        uint16 BPS_divisor = uint16(protocol.BPS_DIVISOR());
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidProtocolFeeBps.selector, BPS_divisor + 1));
        protocol.setFeeBps(BPS_divisor + 1);
        protocol.setFeeBps(0);
        protocol.initiateDeposit(1000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
    }

    function test_setFeeCollector() public {
        vm.expectRevert(UsdnProtocolInvalidFeeCollector.selector);
        protocol.setFeeCollector(address(0));
        protocol.setFeeCollector(address(this));
    }

    function test_pendingProtocolFee() public {
        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
        protocol.initiateDeposit(1000 ether, abi.encode(DEFAULT_PARAMS.initialPrice), "");
        protocol.validateDeposit(abi.encode(DEFAULT_PARAMS.initialPrice), "");
        assertGt(protocol.pendingProtocolFee(), 0, "pending protocol fee after deposit");
    }
}
