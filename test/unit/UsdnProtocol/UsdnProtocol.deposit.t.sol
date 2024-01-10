// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract TestUsdnProtocolDeposit is UsdnProtocolBaseFixture {
    uint256 constant INITIAL_WSTETH_BALANCE = 10 ether;

    function setUp() public override {
        super.setUp();
        wstETH.mint(address(this), INITIAL_WSTETH_BALANCE);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    function test_initiateDeposit() public {
        skip(3600);
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2500 ether));

        vm.expectEmit(true, true, false, false);
        emit InitiatedDeposit(address(this), depositAmount); // expected event
        protocol.initiateDeposit(depositAmount, currentPrice, hex"");

        assertEq(wstETH.balanceOf(address(this)), INITIAL_WSTETH_BALANCE - depositAmount, "wstETH user balance");
        assertEq(
            wstETH.balanceOf(address(protocol)),
            INITIAL_DEPOSIT + INITIAL_LONG + depositAmount,
            "wstETH protocol balance"
        );
        // no USDN should be minted yet
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply, "usdn total supply");
        // the pending action should not yet be actionable by a third party
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.InitiateDeposit, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.amountOrIndex, depositAmount, "action amount");
    }
}
