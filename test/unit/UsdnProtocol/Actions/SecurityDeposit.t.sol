// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { console2 } from "forge-std/Test.sol";

/**
 * @custom:feature The security deposit of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A security deposit of 0.5 ether
 */
// TO DO : test with multiple users and mor than SECURITY_DEPOSIT_VALUE and error msg in assertEq
contract TestUsdnProtocolOpenPosition is UsdnProtocolBaseFixture {
    uint256 internal SECURITY_DEPOSIT_VALUE;
    bytes priceData;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);
        priceData = abi.encode(params.initialPrice);

        SECURITY_DEPOSIT_VALUE = protocol.getSecurityDepositValue();
        assertGt(SECURITY_DEPOSIT_VALUE, 0);
    }

    /**
     * @custom:scenario The user initiates and validates an deposit action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialisation of the deposit
     * @custom:and The protocol returns the security deposit to the user at the validation of the deposit
     */
    function test_securityDeposit_deposit() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user initiates an deposit action with less than the security deposit value
     * @custom:when The user initiates an deposit with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_deposit() public {
        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE - 1 }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user0 initiates an deposit action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the deposit
     * @custom:and The protocol returns the security deposit to the user1 at the initialisation of his deposit
     */
    function test_securityDeposit_initiateDeposit_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, previousActionsData);
        _waitDelay();

        assertEq(USER_1.balance, balanceUser1Before);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        vm.prank(USER_1);
        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    /**
     * @custom:scenario The user0 initiates an open position action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the open position
     * @custom:and The protocol returns the security deposit to the user1 at the initialisation of his open position
     */
    function test_securityDeposit_validateDeposit_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(USER_1.balance, balanceUser1Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.validateDeposit(priceData, previousActionsData);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    /**
     * @custom:scenario The user initiates and validates an withdrawal action
     * @custom:given The value of security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialisation of the withdrawal
     * @custom:and The protocol returns the security deposit to the user at the initialisation of the withdrawal
     */
    function test_securityDeposit_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        // we initaite a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user initiates an withdrawal action with less than the security deposit value
     * @custom:when The user initiates an withdrawal with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE - 1 }(1, priceData, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user0 initiates an Withdrawal action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the withdrawal
     * @custom:and The protocol returns the security deposit to the user1 at the initialisation of his withdrawal
     */
    function test_securityDeposit_initiateWithdrawal_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        // we initaite a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, previousActionsData);
        _waitDelay();

        assertEq(USER_1.balance, balanceUser1Before);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    /**
     * @custom:scenario The user0 initiates an withdrawal action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the withdrawal
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his withdrawal
     */
    function test_securityDeposit_validateWithdrawal_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        // we initaite a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(USER_1.balance, balanceUser1Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateWithdrawal(priceData, previousActionsData);
        vm.stopPrank();

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    /**
     * @custom:scenario The user initiates and validates an open position action
     * @custom:given The value of security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialisation of the open position
     * @custom:and The protocol returns the security deposit to the user at the validation of the open position
     */
    function test_securityDeposit_openPosition() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user initiates an open position action with less than the security deposit value
     * @custom:when The user initiates an open position with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_openPosition() public {
        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user0 initiates an deposit action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the deposit
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his deposit
     */
    function test_securityDeposit_initaiteOpenPosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of user0 after initiateOpenPosition"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initiateOpenPosition"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, previousActionsData
        );
        _waitDelay();

        assertEq(
            USER_1.balance,
            balanceUser1Before,
            "balance of user1 after his initiateOpenPosition should have user0 SECURITY_DEPOSIT_VALUE"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of user0 after user1 initiateOpenPosition"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after user1 initiateOpenPosition"
        );

        vm.prank(USER_1);
        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of user0 after after all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "balance of the protocol after after all actions should be balanceProtocol of the begining"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "balance of user1 should have SECURITY_DEPOSIT_VALUE more than at the begining"
        );
    }

    /**
     * @custom:scenario The user0 initiates an open position action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the open position
     * @custom:and The protocol returns the security deposit to the user1 at the initialisation of his open position
     */
    function test_securityDeposit_validateOpenPosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(USER_1.balance, balanceUser1Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.validateOpenPosition(priceData, previousActionsData);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    /**
     * @custom:scenario The user initiates and validates an close position action
     * @custom:given The value of security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialisation of the close position
     * @custom:and The protocol returns the security deposit to the user at the validation of the close position
     */
    function test_securityDeposit_closePosition() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick, tickVersion, index, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user initiates an close position action with less than the security deposit value
     * @custom:when The user initiates an close position with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_closePosition() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            tick, tickVersion, index, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user0 initiates an Withdrawal action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the withdrawal
     * @custom:and The protocol returns the security deposit to the user1 at the initialisation of his withdrawal
     */
    function test_securityDeposit_initiateClosePosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );
        (int24 tick1, uint256 tickVersion1, uint256 index1) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick, tickVersion, index, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.startPrank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick1, tickVersion1, index1, 1 ether, priceData, previousActionsData
        );
        _waitDelay();

        assertEq(USER_1.balance, balanceUser1Before);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    /**
     * @custom:scenario The user0 initiates an withdrawal action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialisation of the withdrawal
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his withdrawal
     */
    function test_securityDeposit_validateClosePosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );
        (int24 tick1, uint256 tickVersion1, uint256 index1) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick, tickVersion, index, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        vm.startPrank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick1, tickVersion1, index1, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(USER_1.balance, balanceUser1Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateClosePosition(priceData, previousActionsData);
        vm.stopPrank();

        assertEq(address(this).balance, balanceUser0Before - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore);
        assertEq(USER_1.balance, balanceUser1Before + SECURITY_DEPOSIT_VALUE);
    }

    receive() external payable { }
}
