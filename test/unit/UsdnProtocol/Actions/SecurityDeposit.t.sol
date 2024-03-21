// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, ADMIN } from "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The security deposit of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A security deposit of 0.5 ether
 */
contract TestUsdnProtocolSecurityDeposit is UsdnProtocolBaseFixture {
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

    /* -------------------------------------------------------------------------- */
    /*                             Simple usage tests                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a deposit action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:and The protocol returns the security deposit to the user at the validation of the deposit
     */
    function test_securityDeposit_deposit() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );

        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "balance of the user after validation should be the same than before all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "balance of the protocol after validation should be the same than before all actions"
        );
    }

    /**
     * @custom:scenario The user initiates and validates a withdrawal action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialization of the withdrawal
     * @custom:and The protocol returns the security deposit to the user at the validation of the withdrawal
     */
    function test_securityDeposit_withdrawal() public {
        // we create a position to be able to withdraw
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        // we initiate a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "the user should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "the user should have retrieved his deposit from the protocol at the end"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
    }

    /**
     * @custom:scenario The user initiates and validates a close position action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialization of the close position
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

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "the user should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "the user should have retrieved his deposit from the protocol at the end"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
    }

    /**
     * @custom:scenario The user initiates and validates an open position action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialization of the open position
     * @custom:and The protocol returns the security deposit to the user at the validation of the open position
     */
    function test_securityDeposit_openPosition() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "the user should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "the user should have retrieved his security deposit from the protocol"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than at the beginning"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                   Less than security deposit value tests                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a deposit action with less than the security deposit value
     * @custom:when The user initiates a deposit with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_deposit() public {
        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE - 1 }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates a withdrawal action with less than the security deposit value
     * @custom:when The user initiates a withdrawal with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE - 1 }(1, priceData, EMPTY_PREVIOUS_DATA);
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
     * @custom:scenario The user initiates a close position action with less than the security deposit value
     * @custom:when The user initiates a close position with SECURITY_DEPOSIT_VALUE - 1 value
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

    /* -------------------------------------------------------------------------- */
    /*                   More than security deposit value tests                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a deposit action with more than the security deposit value
     * @custom:when The user initiates a deposit with SECURITY_DEPOSIT_VALUE + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_securityDeposit_gt_deposit() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE + 100 }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    /**
     * @custom:scenario The user initiates a withdrawal action with more than the security deposit value
     * @custom:when The user initiates a withdrawal with SECURITY_DEPOSIT_VALUE + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_securityDeposit_gt_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE + 100 }(1, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with more than the security deposit value
     * @custom:when The user initiates a deposit with SECURITY_DEPOSIT_VALUE + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_securityDeposit_gt_openPosition() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    /**
     * @custom:scenario The user initiates a close position action with more than the security deposit value
     * @custom:when The user initiates a close position with SECURITY_DEPOSIT_VALUE + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_securityDeposit_gt_closePosition() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            tick, tickVersion, index, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                            Multiple users tests                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user0 initiates a deposit action and user1 validates user0 action with a initiateDeposit
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the deposit
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his deposit
     */
    function test_securityDeposit_initiateDeposit_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of the user0 after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, previousActionsData);
        _waitDelay();

        assertEq(
            USER_1.balance,
            balanceUser1Before,
            "user1 should have taken user0 security deposit with his initiate deposit action"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "after user1 initiates, user0 should not have a change in his balance"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should only have user1 security deposit"
        );

        vm.prank(USER_1);
        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a deposit action and user1 validates user0 action with a validateDeposit
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the deposit
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his deposit
     */
    function test_securityDeposit_validateDeposit_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of the user0 after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "user1 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the protocol should have both security deposits"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.validateDeposit(priceData, previousActionsData);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a withdrawal action and user1 validates user0 action with a
     * initiateWithdrawal
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the withdrawal
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his withdrawal
     */
    function test_securityDeposit_initiateWithdrawal_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        // we initiate a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user0 deposit"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, previousActionsData);
        _waitDelay();

        assertEq(
            USER_1.balance,
            balanceUser1Before,
            "user1 should have taken user0 security deposit with his initiate withdrawal action"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "after user1 initiates, user0 should not have a change in his balance"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should only have user1 security deposit"
        );

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
        // we assert that both withdrawals went through
        assertLt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertLt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a withdrawal action and user1 validates user0 action with a
     * validateWithdrawal
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the withdrawal
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his withdrawal
     */
    function test_securityDeposit_validateWithdrawal_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        // we initiate a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(1, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "user1 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the protocol should have both security deposits"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateWithdrawal(priceData, previousActionsData);
        vm.stopPrank();

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
        // we assert that both withdrawals went through
        assertLt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertLt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a open position action and user1 validates user0 action with a
     * initiateOpenPosition
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the open position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his open position
     */
    function test_securityDeposit_initiateOpenPosition_multipleUsers() public {
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
            "balance of the user0 after initiateOpenPosition should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initiateOpenPosition should have SECURITY_DEPOSIT_VALUE more"
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
            "balance of user1 after his initiateOpenPosition should have user0 security deposit"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of user0 should have SECURITY_DEPOSIT_VALUE less than at the beginning"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after user1 open position should have SECURITY_DEPOSIT_VALUE more"
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
            "balance of the protocol after all actions should be balanceProtocol of the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "balance of user1 should have SECURITY_DEPOSIT_VALUE more than at the beginning"
        );
    }

    /**
     * @custom:scenario The user0 initiates an open position action and user1 validates user0 action with a
     * validateOpenPosition
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the open position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his open position
     */
    function test_securityDeposit_validateOpenPosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "user1 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the protocol should have two security deposits"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.validateOpenPosition(priceData, previousActionsData);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
    }

    /**
     * @custom:scenario The user0 initiates a close position action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the close position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his close position
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

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick1, tickVersion1, index1, 1 ether, priceData, previousActionsData
        );
        _waitDelay();

        assertEq(
            USER_1.balance,
            balanceUser1Before,
            "user1 should have taken user0 security deposit with his initiate close position action"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        vm.prank(USER_1);
        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
    }

    /**
     * @custom:scenario The user0 initiates a close position action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the close position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his close position
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

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the protocol should have user deposit"
        );

        vm.startPrank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick1, tickVersion1, index1, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "user1 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the protocol should have two security deposits"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateClosePosition(priceData, previousActionsData);
        vm.stopPrank();

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                 Change of the security deposit value tests                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a deposit action with a change in the security deposit value
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:then We change the value of the security deposit to SECURITY_DEPOSIT_VALUE / 2
     * @custom:and The protocol returns the security deposit to the user at the validation of the deposit
     * @custom:and The user initiates a withdrawal action with the new security deposit value
     */
    function test_securityDeposit_changeValue() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 newSecurityDepositValue = SECURITY_DEPOSIT_VALUE / 2;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );

        vm.prank(ADMIN);
        protocol.setSecurityDepositValue(newSecurityDepositValue);
        assertEq(
            protocol.getSecurityDepositValue(),
            newSecurityDepositValue,
            "the security deposit value should have changed"
        );

        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "balance of the user after validation should be the same than before all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "balance of the protocol after validation should be the same than before all actions"
        );

        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: newSecurityDepositValue }(1, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - newSecurityDepositValue,
            "the user should have paid the new security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + newSecurityDepositValue,
            "the protocol should have the user's new security deposit value"
        );

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "the user should have retrieved his deposit from the protocol at the end"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
    }

    /**
     * @custom:scenario The user0 initiates a deposit action and user1 validates user0 action after a change of
     * the security deposit value
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user0 at the initialization of the deposit
     * @custom:then We skip validation deadline + 1
     * @custom:and We change the value of the security deposit to SECURITY_DEPOSIT_VALUE / 2
     * @custom:and The protocol returns SECURITY_DEPOSIT_VALUE the user1 at the initialization of his deposit
     */
    function test_securityDeposit_changeValue_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);
        uint256 newSecurityDepositValue = SECURITY_DEPOSIT_VALUE / 2;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "balance of the user0 after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );

        vm.prank(ADMIN);
        protocol.setSecurityDepositValue(newSecurityDepositValue);
        assertEq(
            protocol.getSecurityDepositValue(),
            newSecurityDepositValue,
            "the security deposit value should have changed"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: newSecurityDepositValue }(1 ether, priceData, previousActionsData);
        _waitDelay();

        assertEq(
            USER_1.balance,
            balanceUser1Before - newSecurityDepositValue + SECURITY_DEPOSIT_VALUE,
            "user1 should have taken user0 SECURITY_DEPOSIT_VALUE with his initiate close deposit action"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should have paid the security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + newSecurityDepositValue,
            "the protocol should have newSecurityDepositValue"
        );

        vm.prank(USER_1);
        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "user0 should not have retrieved his security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "user1 should have retrieved his security deposit in addition to user0's"
        );
        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    receive() external payable { }
}
