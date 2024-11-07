// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { TestUsdnProtocolInitialize } from "./Initialize.t.sol";
import { TransferCallback } from "./utils/TransferCallback.sol";

/**
 * @custom:feature Test the initialization of the protocol with the callback for the transfer of wstETH
 * @custom:given An uninitialized protocol
 */
contract TestUsdnProtocolInitializeWithCallback is TransferCallback, TestUsdnProtocolInitialize {
    function setUp() public override {
        super.setUp();
        wstETH.mintAndApprove(address(this), 0, address(protocol), 0);
    }

    /**
     * @custom:scenario Deployer creates an initial deposit via the internal function by using callback for the transfer
     * of wstETH
     * @custom:when The deployer calls the internal function to create an initial deposit without transferring the
     * wstETH
     * @custom:then The protocol reverts with `UsdnProtocolPaymentCallbackFailed` error
     */
    function test_RevertWhen_createInitialDepositWithCallbackNoTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.i_createInitialDeposit(INITIAL_DEPOSIT, INITIAL_PRICE);
    }

    /**
     * @custom:scenario Deployer creates an initial position via the internal function by using callback for the
     * transfer of wstETH
     * @custom:when The deployer calls the internal function to create an initial position without transferring the
     * wstETH
     * @custom:then The protocol reverts with `UsdnProtocolPaymentCallbackFailed` error
     */
    function test_RevertWhen_createInitialPositionWithCallbackNoTransfer() public {
        int24 tickWithoutPenalty = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        int24 expectedTick = tickWithoutPenalty + int24(protocol.getLiquidationPenalty());
        uint128 posTotalExpo = 2 * INITIAL_POSITION;

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.i_createInitialPosition(INITIAL_POSITION, INITIAL_PRICE, expectedTick, posTotalExpo);
    }

    /**
     * @custom:scenario Deployer creates an initial deposit via the internal function by using callback for the transfer
     * of wstETH
     * @custom:given Refer to the test_createInitialDeposit function for more details.
     * @custom:but The wstETH are transferred via the callback
     */
    function test_createInitialDeposit() public override {
        transferActive = true;
        super.test_createInitialDeposit();
    }

    /**
     * @custom:scenario Deployer creates an initial position via the internal function by using callback for the
     * transfer of wstETH
     * @custom:given Refer to the test_createInitialPosition function for more details.
     * @custom:but The wstETH are transferred via the callback
     */
    function test_createInitialPosition() public override {
        transferActive = true;
        super.test_createInitialPosition();
    }

    /**
     * @custom:scenario Deployer initializes the protocol and uses the callback for the transfer of wstETH
     * @custom:given Refer to the test_initialize function for more details.
     * @custom:but The wstETH are transferred via the callback
     */
    function test_initialize() public override {
        transferActive = true;
        super.test_initialize();
    }

    /**
     * @custom:scenario Send too much ether while initializing and use the callback for the transfer of wstETH
     * @custom:given Refer to the test_initializeRefundEther function for more details.
     * @custom:but The wstETH are transferred via the callback
     */
    function test_initializeRefundEther() public override {
        transferActive = true;
        super.test_initializeRefundEther();
    }
}
