// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    Position,
    PendingAction,
    ProtocolAction,
    LongPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The entry/exit position fees mechanism of the protocol
 */
contract TestUsdnProtocolEntryExitFees is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10_000 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                         Open / close long position                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a position opening
     * @custom:given The price of the asset is $2000
     * @custom:and The liquidation price is $2500
     * @custom:when The user initiates a position opening with 500 wstETH as collateral
     * @custom:then The protocol emit an event with the correct price including the fees
     * @custom:and The user's position leverage is computed using the price with fees (with
     *             Chainlink oracle price)
     * @dev The price with fees is used only for data in the event emitted at this point so we just
     *      need to check the event data at this point
     */
    function test_initiateOpenPosition() public {
        uint128 desiredLiqPrice =
            protocol.getLiquidationPrice(2500 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));

        uint256 expectedPrice = 2000 ether + 2000 ether * protocol.positionFee() / protocol.BPS_DIVISOR();
        vm.expectEmit(true, false, false, true);
        emit InitiatedOpenPosition(
            address(this),
            uint40(block.timestamp),
            2_574_742_120_503_060_520_416,
            1 ether,
            uint128(expectedPrice),
            71_300,
            0,
            0
        );

        bytes memory priceData = abi.encode(2000 ether);
        protocol.initiateOpenPosition(1 ether, desiredLiqPrice, priceData, "");
    }

    /**
     * @custom:scenario The user initiates and validate a position opening
     * @custom:given The price of the asset is $2000
     * @custom:and The liquidation price is $2500
     * @custom:when The user initiates a position opening with 500 wstETH as collateral
     * @custom:when The user validate his position opening with
     * @custom:then The user leverage should be computed using the price with fees (with Pyth oracle
     *              price)
     * @dev The price with fees is used only for data in the event emitted at this point so we just
     *      need to check the event data at this point
     */
    function test_validateOpenPosition() public {
        uint128 desiredLiqPrice =
            protocol.getLiquidationPrice(2500 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));

        bytes memory priceData = abi.encode(2000 ether);
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, desiredLiqPrice, priceData, "");

        skip(50);

        protocol.validateOpenPosition(priceData, "");

        Position memory long = protocol.getLongPosition(tick, tickVersion, index);

        assertEq(long.leverage, 2_575_521_522_284_192_036_538, "leverage");
    }

    /**
     * @custom:scenario The user initiates a position opening and then initiate and validate a
     *               position closing
     * @custom:given The price of the asset is $2000
     * @custom:and The liquidation price is $2500
     * @custom:when The user initiates a position opening with 500 wstETH as collateral
     * @custom:then The user leverage should be computed using the price with fees (with Pyth oracle
     *              price)
     * @custom:and The user should be able to initiate a position closing
     * @custom:then The user should be able to validate his position closing
     * @custom:and The pending action asset to transfer should be computed using the price with fees
     */
    function test_initiateClosePosition() public {
        uint128 desiredLiqPrice =
            protocol.getLiquidationPrice(2500 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));

        bytes memory priceData = abi.encode(2000 ether);
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, desiredLiqPrice, priceData, "");

        skip(50);

        protocol.validateOpenPosition(priceData, "");

        skip(3600);

        protocol.initiateClosePosition(tick, tickVersion, index, priceData, "");

        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getUserPendingAction(address(this));

        assertEq(action.var6, 998_752_024_228_666_563, "Computed asset to transfer");
    }

    /**
     * @custom:scenario The user initiates a position opening and then initiate and validate a
     *               position closing, and then validate the position closing
     * @custom:given The price of the asset is $2000
     * @custom:and The liquidation price is $2500
     * @custom:when The user initiates a position opening with 500 wstETH as collateral
     * @custom:then The user leverage should be computed using the price with fees (with Pyth oracle
     *              price)
     * @custom:and The user should be able to initiate a position closing
     * @custom:then The user should be able to validate his position closing
     * @custom:and The pending action asset to transfer should be computed using the price with fees
     * @custom:and The user's wstETH balance should be updated accordingly
     */
    function test_validateClosePosition() public {
        uint128 desiredLiqPrice =
            protocol.getLiquidationPrice(2500 ether, uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS()));

        bytes memory priceData = abi.encode(2000 ether);
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, desiredLiqPrice, priceData, "");

        skip(50);

        protocol.validateOpenPosition(priceData, "");

        skip(3600);

        protocol.initiateClosePosition(tick, tickVersion, index, priceData, "");

        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getUserPendingAction(address(this));

        assertEq(action.var6, 998_752_024_228_666_563, "Computed asset to transfer");

        uint256 balanceBefore = wstETH.balanceOf(address(this));

        protocol.validateClosePosition(priceData, "");

        uint256 balanceAfter = wstETH.balanceOf(address(this));

        assertEq(balanceAfter - balanceBefore, 998_752_024_228_666_563, "wstETH balance");
    }

    /* -------------------------------------------------------------------------- */
    /*                             Deposit / withdraw                             */
    /* -------------------------------------------------------------------------- */

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
