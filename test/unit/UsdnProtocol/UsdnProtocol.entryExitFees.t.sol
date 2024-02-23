// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The entry/exit position fees mechanism of the protocol
 */
contract TestUsdnProtocolEntryExitFees is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's position should have a start price according to the fees
     */
    function test_initiateDepositPositionFees() public {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, "");
        
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        uint256 expectedPrice = 2000 ether - 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        // Check stored position asset price
        assertEq(action.var2, expectedPrice, "assetPrice");
    }

    /**
     * @custom:scenario The user validate a deposit of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's position should have a start price according to the fees
     * @custom:and The user's USDN balance should be updated accordingly
     */
    function test_validateDepositPositionFees() public {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, "");
        
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        uint256 expectedPrice = 2000 ether - 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        // Check stored position asset price
        assertEq(action.var2, expectedPrice, "assetPrice");

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(currentPrice, "");
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));

        assertEq(usdnBalanceAfter - usdnBalanceBefore, expectedPrice, "usdn balance");
    }

    /**
     * @custom:scenario The user initiates a withdraw of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's position should have a start price according to the fees
     * @custom:and The user's USDN balance should be updated accordingly
     * @custom:and The user's withdrawal pending position should have a start price according to the fees
     */
    function test_initiateWithdrawalPositionFees() public {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, "");
        
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        uint256 expectedPrice = 2000 ether - 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        // Check stored position asset price
        assertEq(action.var2, expectedPrice, "assetPrice");

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(currentPrice, "");
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));

        assertEq(usdnBalanceAfter - usdnBalanceBefore, expectedPrice, "usdn balance");

        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(depositAmount, currentPrice, "");

        vm.prank(address(0)); // simulate front-end call by someone else
        action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        expectedPrice = 2000 ether + 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        // Check stored position asset price
        assertEq(action.var2, expectedPrice, "assetPrice");
    }

    /**
     * @custom:scenario The user initiates a withdraw of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's position should have a start price according to the fees
     * @custom:and The user's USDN balance should be updated accordingly
     * @custom:and The user's withdrawal pending position should have a start price according to the fees
     * @custom:and The user's withdrawal pending USDN balance should be updated accordingly
     */
    function test_validateWithdrawalPositionFees() public {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, "");
        
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        uint256 expectedPrice = 2000 ether - 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        // Check stored position asset price
        assertEq(action.var2, expectedPrice, "assetPrice");

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(currentPrice, "");
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));

        assertEq(usdnBalanceAfter - usdnBalanceBefore, expectedPrice, "usdn balance");

        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(depositAmount, currentPrice, "");

        vm.prank(address(0)); // simulate front-end call by someone else
        action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        expectedPrice = 2000 ether + 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        // Check stored position asset price
        assertEq(action.var2, expectedPrice, "assetPrice");

        usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateWithdrawal(currentPrice, "");
        usdnBalanceAfter = usdn.balanceOf(address(this));

        assertEq(usdnBalanceAfter - usdnBalanceBefore, 0, "usdn balance");
    }
}
