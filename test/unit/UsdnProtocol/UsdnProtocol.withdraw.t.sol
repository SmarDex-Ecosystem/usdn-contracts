// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The withdraw function of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolWithdraw is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint128 internal constant USDN_AMOUNT = 1000 ether;
    uint256 internal initialWstETHBalance;
    uint256 internal initialUsdnBalance;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), INITIAL_WSTETH_BALANCE);
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at price $2000
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        protocol.initiateDeposit(DEPOSIT_AMOUNT, currentPrice, "");
        _waitDelay();
        protocol.validateDeposit(currentPrice, "");
        initialUsdnBalance = usdn.balanceOf(address(this));
        initialWstETHBalance = wstETH.balanceOf(address(this));
    }

    /**
     * @custom:scenario Test the setup function output
     * @custom:given The user deposited 1 wstETH at price $2000
     * @custom:then The user's USDN balance is 2000 USDN
     * @custom:and The user's wstETH balance is 9 wstETH
     */
    function test_withdrawSetUp() public {
        assertEq(initialUsdnBalance, 2000 * DEPOSIT_AMOUNT, "initial usdn balance");
        assertEq(initialWstETHBalance, INITIAL_WSTETH_BALANCE - DEPOSIT_AMOUNT, "initial wstETH balance");
    }

    /**
     * @custom:scenario The user initiates a withdrawal for 1000 USDN
     * @custom:given The price of the asset is $3000
     * @custom:when The user initiates a withdraw for 1000 USDN
     * @custom:then The user's USDN balance decreases by 1000 USDN
     * @custom:and The protocol's USDN balance increases by 1000 USDN
     * @custom:and The protocol emits an `InitiatedWithdrawal` event
     * @custom:and The USDN total supply does not change yet
     * @custom:and The protocol's wstETH balance does not change yet
     * @custom:and The user has a pending action of type `InitiateWithdrawal` with the amount of 1000 USDN
     * @custom:and The pending action is not actionable yet
     * @custom:and The pending action is actionable after the validation deadline has elapsed
     */
    function test_initiateWithdraw() public {
        skip(3600);
        bytes memory currentPrice = abi.encode(uint128(3000 ether));

        vm.expectEmit();
        emit InitiatedWithdrawal(address(this), USDN_AMOUNT); // expected event
        protocol.initiateWithdrawal(USDN_AMOUNT, currentPrice, "");

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "usdn user balance");
        assertEq(usdn.balanceOf(address(protocol)), USDN_AMOUNT, "usdn protocol balance");
        // no wstETH should be given to the user yet
        assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance, "wstETH user balance");
        // no USDN should be burned yet
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + initialUsdnBalance, "usdn total supply");
        // the pending action should not yet be actionable by a third party
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.amount, USDN_AMOUNT, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        vm.prank(address(0)); // simulate front-end call by someone else
        action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(this), "pending action user");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 0 USDN
     * @custom:when The user validates a withdrawal for 0 USDN
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateWithdrawal(0, currentPrice, "");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price increases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $3000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.425411621694649837
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.425411621694649837
     */
    function test_validateWithdrawPriceUp() public {
        skip(3600);
        _checkValidateWithdrawWithPrice(uint128(2500 ether), uint128(3000 ether), 0.425411621694649837 ether);
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price decreases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $2000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.455220982334125330
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.455220982334125330
     */
    function test_validateWithdrawPriceDown() public {
        skip(3600);
        _checkValidateWithdrawWithPrice(uint128(2500 ether), uint128(2000 ether), 0.45522098233412533 ether);
    }

    /**
     * @custom:scenario The user sends too much ether when initiating a withdrawal
     * @custom:given The user withdraws 1 wstETH
     * @custom:when The user sends 0.5 ether as value in the `initiateWithdrawal` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_initiateWithdrawEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        uint256 balanceBefore = address(this).balance;
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateWithdrawal);
        protocol.initiateWithdrawal{ value: validationCost }(USDN_AMOUNT, currentPrice, "");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user sends too much ether when validating a withdrawal
     * @custom:given The user initiated a withdrawal of 1000 USDN and validates it
     * @custom:when The user sends 0.5 ether as value in the `validateWithdrawal` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_validateWithdrawEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        // initiate
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateWithdrawal);
        protocol.initiateWithdrawal{ value: validationCost }(USDN_AMOUNT, currentPrice, "");

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateWithdrawal);
        uint256 balanceBefore = address(this).balance;
        protocol.validateWithdrawal{ value: 0.5 ether }(currentPrice, "");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @dev Create a withdrawal at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted
     * event and the resulting state.
     * @param initialPrice price of the asset at the time of withdrawal initiation
     * @param assetPrice price of the asset at the time of withdrawal validation
     * @param expectedAssetAmount expected amount of asset withdrawn
     */
    function _checkValidateWithdrawWithPrice(uint128 initialPrice, uint128 assetPrice, uint256 expectedAssetAmount)
        public
    {
        bytes memory currentPrice = abi.encode(initialPrice);
        protocol.initiateWithdrawal(USDN_AMOUNT, currentPrice, "");

        uint256 vaultBalance = protocol.getBalanceVault(); // save for withdrawn amount calculation in case price
            // decreases

        // wait the required delay between initiation and validation
        _waitDelay();

        currentPrice = abi.encode(assetPrice);

        // if price increases, we need to use the new balance to calculate the withdrawn amount
        if (assetPrice > initialPrice) {
            vaultBalance = uint256(protocol.i_vaultAssetAvailable(assetPrice));
        }

        // theoretical withdrawn amount
        uint256 withdrawnAmount = uint256(USDN_AMOUNT) * vaultBalance / usdn.totalSupply();
        assertEq(withdrawnAmount, expectedAssetAmount, "asset amount");

        vm.expectEmit();
        emit ValidatedWithdrawal(address(this), withdrawnAmount, USDN_AMOUNT); // expected event
        protocol.validateWithdrawal(currentPrice, "");

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "final usdn balance");
        assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance + withdrawnAmount, "final wstETH balance");
    }

    // test refunds
    receive() external payable { }
}
