// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, ADMIN } from "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    PreviousActionsData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The security deposit of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A security deposit of 0.5 ether
 */
contract TestUsdnProtocolSecurityDeposit is UsdnProtocolBaseFixture {
    uint64 internal SECURITY_DEPOSIT_VALUE;
    bytes priceData;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);
        priceData = abi.encode(params.initialPrice);

        SECURITY_DEPOSIT_VALUE = protocol.getSecurityDepositValue();
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

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);

        protocol.validateDeposit(address(this), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd(balanceSenderBefore, balanceProtocolBefore);
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
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);

        protocol.validateWithdrawal(address(this), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd(balanceSenderBefore, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user initiates and validates a close position action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from the user at the initialization of the close position
     * @custom:and The protocol returns the security deposit to the user at the validation of the close position
     */
    function test_securityDeposit_closePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId, 1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);

        protocol.validateClosePosition(address(this), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd(balanceSenderBefore, balanceProtocolBefore);
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
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);

        protocol.validateOpenPosition(address(this), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd(balanceSenderBefore, balanceProtocolBefore);
    }

    /**
     * @custom:scenario Two users initiate an open position and deposit actions, and a third user validates both
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:then The protocol takes the security deposit from both users at their initializations
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns both security deposits to the third user when
     * validateActionablePendingActions is called
     */
    function test_securityDeposit_validateActionablePendingActions() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser2Before = USER_2.balance;

        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInLong(
            OpenParams({
                user: USER_2,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        skip(protocol.getValidationDeadline() + 1);

        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the protocol should have two security deposits"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "the user1 should have paid the security deposit"
        );
        assertEq(
            USER_2.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "the user2 should have paid the security deposit"
        );

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(address(this));
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        previousPriceData[1] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateActionablePendingActions(previousActionsData, 10);

        assertEq(
            address(this).balance,
            balanceSenderBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the user0 should have retrieved both security deposits from the protocol"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than at the beginning"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "the user1 should not have retrieved his security deposit"
        );
        assertEq(
            USER_2.balance,
            balanceUser2Before - SECURITY_DEPOSIT_VALUE,
            "the user2 should not have retrieved his security deposit"
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
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
    }

    /**
     * @custom:scenario The user initiates a withdrawal action with less than the security deposit value
     * @custom:when The user initiates a withdrawal with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
    }

    /**
     * @custom:scenario The user initiates an open position action with less than the security deposit value
     * @custom:when The user initiates an open position with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_openPosition() public {
        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
    }

    /**
     * @custom:scenario The user initiates a close position action with less than the security deposit value
     * @custom:when The user initiates a close position with SECURITY_DEPOSIT_VALUE - 1 value
     * @custom:then The protocol reverts with UsdnProtocolSecurityDepositTooLow
     */
    function test_RevertWhen_secDec_lt_closePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            posId, 1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
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

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);
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
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            1, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);
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
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user initiates a close position action with more than the security deposit value
     * @custom:when The user initiates a close position with SECURITY_DEPOSIT_VALUE + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_securityDeposit_gt_closePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            posId, 1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Multiple users tests                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user0 initiates a deposit action and user1 validates user0 action with a initiateDeposit
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the deposit
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

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, previousActionsData, USER_1, USER_1
        );
        _waitDelay();

        assertRefundEthToUser1(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        vm.prank(USER_1);
        protocol.validateDeposit(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a deposit action and user1 validates user0 action with a validateDeposit
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the deposit
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

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, USER_1, USER_1
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaidTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.validateDeposit(USER_1, priceData, previousActionsData);

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a withdrawal action and user1 validates user0 action with a
     * initiateWithdrawal
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the withdrawal
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

        // we initiate a withdrawal for 1e18 shares of USDN
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18, priceData, previousActionsData, USER_1, USER_1
        );
        _waitDelay();

        assertRefundEthToUser1(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        protocol.validateWithdrawal(USER_1, priceData, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        // we assert that both withdrawals went through
        assertLt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertLt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a withdrawal action and user1 validates user0 action with a
     * validateWithdrawal
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the withdrawal
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

        // we initiate a withdrawal for 1e18 sahres of USDN
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18, priceData, EMPTY_PREVIOUS_DATA, USER_1, USER_1
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaidTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateWithdrawal(USER_1, priceData, previousActionsData);
        vm.stopPrank();

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        // we assert that both withdrawals went through
        assertLt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertLt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a open position action and user1 validates user0 action with a
     * initiateOpenPosition
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the open position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his open position
     */
    function test_securityDeposit_initiateOpenPosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, previousActionsData, USER_1, USER_1
        );
        _waitDelay();

        assertRefundEthToUser1(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        vm.prank(USER_1);
        protocol.validateOpenPosition(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user0 initiates an open position action and user1 validates user0 action with a
     * validateOpenPosition
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the open position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his open position
     */
    function test_securityDeposit_validateOpenPosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA, address(this), USER_1
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaidTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.validateOpenPosition(USER_1, priceData, previousActionsData);

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user0 initiates a close position action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the close position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his close position
     */
    function test_securityDeposit_initiateClosePosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint256 balanceUser1Before = USER_1.balance;

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        PositionId memory posId1 = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId, 1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        vm.prank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId1, 1 ether, priceData, previousActionsData, USER_1, USER_1
        );
        _waitDelay();

        assertRefundEthToUser1(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        vm.prank(USER_1);
        protocol.validateClosePosition(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);
    }

    /**
     * @custom:scenario The user0 initiates a close position action and user1 validates user0 action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the close position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his close position
     */
    function test_securityDeposit_validateClosePosition_multipleUsers() public {
        wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        uint256 balanceUser1Before = USER_1.balance;
        uint256 balanceUser0Before = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        PositionId memory posId1 = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId, 1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

        vm.startPrank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId1, 1 ether, priceData, EMPTY_PREVIOUS_DATA, USER_1, USER_1
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaidTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        (, uint128[] memory rawIndices) = protocol.getActionablePendingActions(USER_1);
        bytes[] memory previousPriceData = new bytes[](rawIndices.length);
        previousPriceData[0] = priceData;
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });

        protocol.validateClosePosition(USER_1, priceData, previousActionsData);
        vm.stopPrank();

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);
    }

    /* -------------------------------------------------------------------------- */
    /*                 Change of the security deposit value tests                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a deposit action with a change in the security deposit value
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:then We change the value of the security deposit to SECURITY_DEPOSIT_VALUE / 2
     * @custom:and The protocol returns the security deposit to the user at the validation of the deposit
     * @custom:and The user initiates a withdrawal action with the new security deposit value
     */
    function test_securityDeposit_changeValue() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        uint64 newSecurityDepositValue = SECURITY_DEPOSIT_VALUE / 2;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);

        vm.prank(ADMIN);
        protocol.setSecurityDepositValue(newSecurityDepositValue);
        assertEq(
            protocol.getSecurityDepositValue(),
            newSecurityDepositValue,
            "the security deposit value should have changed"
        );

        protocol.validateDeposit(address(this), priceData, EMPTY_PREVIOUS_DATA);

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
        protocol.initiateWithdrawal{ value: newSecurityDepositValue }(
            1, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
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

        protocol.validateWithdrawal(address(this), priceData, EMPTY_PREVIOUS_DATA);

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
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the deposit
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
        uint64 newSecurityDepositValue = SECURITY_DEPOSIT_VALUE / 2;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        skip(protocol.getValidationDeadline() + 1);

        assertSecurityDepositPaid(balanceUser0Before, balanceProtocolBefore);

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
        protocol.initiateDeposit{ value: newSecurityDepositValue }(
            1 ether, priceData, previousActionsData, USER_1, USER_1
        );
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
        protocol.validateDeposit(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers(balanceUser0Before, balanceUser1Before, balanceProtocolBefore);

        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /* -------------------------------------------------------------------------- */
    /*                         stale pending actions tests                        */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a deposit action
     * @custom:given The value of the security deposit is SECURITY_DEPOSIT_VALUE
     * @custom:when The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:then The protocol returns the security deposit to the user at the validation of the deposit
     */
    function test_securityDeposit_refundStaleTransaction() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        PositionId memory posId = _createStalePendingActionHelper();

        assertSecurityDepositPaid(balanceSenderBefore, balanceProtocolBefore);

        wstETH.approve(address(protocol), 1 ether);
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, priceData, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "the user should have retrieved his first security deposit from the stale pending action"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the balance of the protocol after the second initialization should have only one security deposit"
        );

        protocol.validateDeposit(address(this), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd(balanceSenderBefore, balanceProtocolBefore);
    }

    /* -------------------------------------------------------------------------- */
    /*                                test helpers                                */
    /* -------------------------------------------------------------------------- */

    function assertSecurityDepositPaid(uint256 balanceSenderBefore, uint256 balanceProtocolBefore) public {
        assertEq(
            address(this).balance,
            balanceSenderBefore - SECURITY_DEPOSIT_VALUE,
            "the balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    function assertBalancesEnd(uint256 balanceSenderBefore, uint256 balanceProtocolBefore) public {
        assertEq(
            address(this).balance,
            balanceSenderBefore,
            "the balance of the user after all actions should be the same than before all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the balance of the protocol after all actions should be the same than before all actions"
        );
    }

    function assertBalancesEndTwoUsers(
        uint256 balanceUser0Before,
        uint256 balanceUser1Before,
        uint256 balanceProtocolBefore
    ) public {
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the user0 should not have retrieved his security deposit"
        );
        assertEq(
            USER_1.balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "the user1 should have retrieved his security deposit in addition to user0's"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the protocol balance after all actions should be the same than a the beginning"
        );
    }

    function assertRefundEthToUser1(
        uint256 balanceUser0Before,
        uint256 balanceUser1Before,
        uint256 balanceProtocolBefore
    ) public {
        assertEq(
            USER_1.balance,
            balanceUser1Before,
            "the balance of user1 after his action should have user0 security deposit"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the balance of user0 should have SECURITY_DEPOSIT_VALUE less than at the beginning"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the balance of the protocol after user1 action should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    function assertSecurityDepositPaidTwoUsers(
        uint256 balanceUser0Before,
        uint256 balanceUser1Before,
        uint256 balanceProtocolBefore
    ) public {
        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "the user1 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the user0 should have paid the security deposit to the protocol"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + 2 * SECURITY_DEPOSIT_VALUE,
            "the protocol should have two security deposits in balance"
        );
    }

    receive() external payable { }
}
