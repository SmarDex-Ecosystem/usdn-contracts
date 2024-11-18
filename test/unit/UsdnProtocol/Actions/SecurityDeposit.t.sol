// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolImpl } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolImpl.sol";
import { IUsdnProtocolTypes } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The security deposit of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A security deposit of 0.5 ether
 */
contract TestUsdnProtocolSecurityDeposit is UsdnProtocolBaseFixture {
    DummyContract receiverContract = new DummyContract();
    uint64 internal SECURITY_DEPOSIT_VALUE;
    bytes priceData;
    uint256 balanceUser0Before;
    uint256 balanceUser1Before;
    uint256 balanceProtocolBefore;
    uint256 balanceReceiverContractBefore;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 1000 ether, address(protocol), type(uint256).max);

        priceData = abi.encode(params.initialPrice);

        SECURITY_DEPOSIT_VALUE = protocol.getSecurityDepositValue();
    }

    /* -------------------------------------------------------------------------- */
    /*                             Simple usage tests                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a `deposit` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:then The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:and The protocol returns the security deposit to the user at the validation of the deposit
     */
    function test_deposit() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();

        protocol.validateDeposit(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd();
    }

    /**
     * @custom:scenario The user initiates and validates a `withdraw` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:then The protocol takes the security deposit from the user at the initialization of the withdrawal
     * @custom:and The protocol returns the security deposit to the user at the validation of the withdrawal
     */
    function test_withdrawal() public {
        // we create a position to be able to withdraw
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        // we initiate a 1 wei withdrawal
        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();

        protocol.validateWithdrawal(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd();
    }

    /**
     * @custom:scenario The user initiates and validates a `close` position action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:then The protocol takes the security deposit from the user at the initialization of the close position
     * @custom:and The protocol returns the security deposit to the user at the validation of the close position
     */
    function test_closePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
        _waitDelay();

        assertSecurityDepositPaid();

        protocol.validateClosePosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd();
    }

    /**
     * @custom:scenario The user initiates and validates an `open` position action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:then The protocol takes the security deposit from the user at the initialization of the open position
     * @custom:and The protocol returns the security deposit to the user at the validation of the open position
     */
    function test_openPosition() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();

        protocol.validateOpenPosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd();
    }

    /**
     * @custom:scenario Two users initiate an `open` position and `deposit` actions, and a third user validates both
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:then The protocol takes the security deposit from both users at their initializations
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns both security deposits to the third user when
     * validateActionablePendingActions is called
     */
    function test_validateActionablePendingActions() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();
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
        _waitBeforeActionablePendingAction();

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

        vm.expectEmit();
        emit SecurityDepositRefunded(USER_1, address(this), SECURITY_DEPOSIT_VALUE);
        vm.expectEmit();
        emit SecurityDepositRefunded(USER_2, address(this), SECURITY_DEPOSIT_VALUE);
        protocol.validateActionablePendingActions(previousActionsData, 10);

        assertEq(
            address(this).balance,
            balanceUser0Before + 2 * SECURITY_DEPOSIT_VALUE,
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
     * @custom:scenario The user initiates a `deposit` action with less than the security deposit value
     * @custom:when The user initiates a deposit with `SECURITY_DEPOSIT_VALUE` - 1 value
     * @custom:then The protocol reverts with {UsdnProtocolSecurityDepositTooLow}
     */
    function test_RevertWhen_securityDeposit_lt_deposit() public {
        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates a `withdraw` action with less than the security deposit value
     * @custom:when The user initiates a withdrawal with `SECURITY_DEPOSIT_VALUE` - 1 value
     * @custom:then The protocol reverts with {UsdnProtocolSecurityDepositTooLow}
     */
    function test_RevertWhen_securityDeposit_lt_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates an `open` position action with less than the security deposit value
     * @custom:when The user initiates an `open` position with `SECURITY_DEPOSIT_VALUE` - 1 value
     * @custom:then The protocol reverts with {UsdnProtocolSecurityDepositTooLow}
     */
    function test_RevertWhen_securityDeposit_lt_openPosition() public {
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(UsdnProtocolSecurityDepositTooLow.selector);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE - 1 }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates a close position action with less than the security deposit value
     * @custom:when The user initiates a close position with `SECURITY_DEPOSIT_VALUE` - 1 value
     * @custom:then The protocol reverts with {UsdnProtocolSecurityDepositTooLow}
     */
    function test_RevertWhen_securityDeposit_lt_closePosition() public {
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
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                   More than security deposit value tests                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a `deposit` action with more than the security deposit value
     * @custom:when The user initiates a deposit with `SECURITY_DEPOSIT_VALUE` + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_gt_deposit() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();
    }

    /**
     * @custom:scenario The user initiates a `withdraw` action with more than the security deposit value
     * @custom:when The user initiates a withdrawal with `SECURITY_DEPOSIT_VALUE` + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_gt_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            1,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();
    }

    /**
     * @custom:scenario The user initiates an `open` position action with more than the security deposit value
     * @custom:when The user initiates a deposit with `SECURITY_DEPOSIT_VALUE` + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_gt_openPosition() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        assertSecurityDepositPaid();
    }

    /**
     * @custom:scenario The user initiates a close position action with more than the security deposit value
     * @custom:when The user initiates a close position with `SECURITY_DEPOSIT_VALUE` + 100 value
     * @custom:then The protocol refunds the excess to the user
     */
    function test_gt_closePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE + 100 }(
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
        _waitDelay();

        assertSecurityDepositPaid();
    }

    /* -------------------------------------------------------------------------- */
    /*                            Multiple users tests                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user0 initiates a `deposit` action and user1 validates user0 action with a {initiateDeposit}
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the deposit
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his deposit
     */
    function test_initiateDeposit_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaid();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, priceData, previousActionsData
        );
        _waitDelay();

        assertRefundEthToUser1();

        vm.prank(USER_1);
        protocol.validateDeposit(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers();

        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a `deposit` action and user1 validates user0 action with a {validateDeposit}
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the deposit
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his deposit
     */
    function test_validateDeposit_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        assertSecurityDepositPaid();

        vm.prank(USER_1);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaidTwoUsers();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        vm.prank(USER_1);
        protocol.validateDeposit(USER_1, priceData, previousActionsData);

        assertBalancesEndTwoUsers();

        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a `withdraw` action and user1 validates user0 action with a
     * {initiateWithdrawal}
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the withdrawal
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his withdrawal
     */
    function test_initiateWithdrawal_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        // we initiate a withdrawal for 1e18 shares of USDN
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaid();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 2);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18, DISABLE_AMOUNT_OUT_MIN, USER_1, USER_1, type(uint256).max, priceData, previousActionsData
        );

        _waitDelay();

        assertRefundEthToUser1();

        protocol.validateWithdrawal(USER_1, priceData, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        assertBalancesEndTwoUsers();

        // we assert that both withdrawals went through
        assertLt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertLt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a `withdraw` action and user1 validates user0 action with a
     * {validateWithdrawal}
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the withdrawal
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his withdrawal
     */
    function test_validateWithdrawal_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);

        // we initiate a withdrawal for 1e18 shares of USDN
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();

        vm.startPrank(USER_1);
        usdn.approve(address(protocol), 2);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1e18, DISABLE_AMOUNT_OUT_MIN, USER_1, USER_1, type(uint256).max, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaidTwoUsers();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        protocol.validateWithdrawal(USER_1, priceData, previousActionsData);
        vm.stopPrank();

        assertBalancesEndTwoUsers();

        // we assert that both withdrawals went through
        assertLt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertLt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /**
     * @custom:scenario The user0 initiates a open position action and user1 validates user0 action with a
     * {initiateOpenPosition}
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the open position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his open position
     */
    function test_initiateOpenPosition_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaid();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        uint256 leverage = protocol.getMaxLeverage();
        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            leverage,
            USER_1,
            USER_1,
            type(uint256).max,
            priceData,
            previousActionsData
        );
        _waitDelay();

        assertRefundEthToUser1();

        vm.prank(USER_1);
        protocol.validateOpenPosition(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers();
    }

    /**
     * @custom:scenario The user0 initiates an `open` position action and user1 validates user0 action with a
     * {validateOpenPosition}
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the open position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his open position
     */
    function test_validateOpenPosition_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        assertSecurityDepositPaid();
        uint256 leverage = protocol.getMaxLeverage();
        vm.prank(USER_1);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            leverage,
            address(this),
            USER_1,
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaidTwoUsers();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        vm.prank(USER_1);
        protocol.validateOpenPosition(USER_1, priceData, previousActionsData);

        assertBalancesEndTwoUsers();
    }

    /**
     * @custom:scenario The user0 initiates a close position action and user1 validates user0 action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the close position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the initialization of his close position
     */
    function test_initiateClosePosition_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

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
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaid();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        vm.prank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId1, 1 ether, DISABLE_MIN_PRICE, USER_1, USER_1, type(uint256).max, priceData, previousActionsData, ""
        );
        _waitDelay();

        assertRefundEthToUser1();

        vm.prank(USER_1);
        protocol.validateClosePosition(USER_1, priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEndTwoUsers();
    }

    /**
     * @custom:scenario The user0 initiates a close position action and user1 validates user0 action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the close position
     * @custom:then We skip validation deadline + 1
     * @custom:and The protocol returns the security deposit to the user1 at the validation of his close position
     */
    function test_validateClosePosition_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

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
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );
        _waitDelay();

        assertSecurityDepositPaid();

        vm.startPrank(USER_1);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId1, 1 ether, DISABLE_MIN_PRICE, USER_1, USER_1, type(uint256).max, priceData, EMPTY_PREVIOUS_DATA, ""
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaidTwoUsers();

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        protocol.validateClosePosition(USER_1, priceData, previousActionsData);
        vm.stopPrank();

        assertBalancesEndTwoUsers();
    }

    /* -------------------------------------------------------------------------- */
    /*                 Change of the security deposit value tests                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a `deposit` action with a change in the security deposit value
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:then We change the value of the security deposit to SECURITY_DEPOSIT_VALUE / 2
     * @custom:and The protocol returns the security deposit to the user at the validation of the deposit
     * @custom:and The user initiates a `withdraw` action with the new security deposit value
     */
    function test_changeValue() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();
        uint64 newSecurityDepositValue = SECURITY_DEPOSIT_VALUE / 2;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();

        vm.prank(ADMIN);
        protocol.setSecurityDepositValue(newSecurityDepositValue);
        assertEq(
            protocol.getSecurityDepositValue(),
            newSecurityDepositValue,
            "the security deposit value should have changed"
        );

        protocol.validateDeposit(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before,
            "balance of the user after validation should be the same than before all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "balance of the protocol after validation should be the same than before all actions"
        );

        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: newSecurityDepositValue }(
            1,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceUser0Before - newSecurityDepositValue,
            "the user should have paid the new security deposit"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + newSecurityDepositValue,
            "the protocol should have the user's new security deposit value"
        );

        protocol.validateWithdrawal(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertEq(
            address(this).balance,
            balanceUser0Before,
            "the user should have retrieved his deposit from the protocol at the end"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "protocol balance after all actions should be the same than a the beginning"
        );
    }

    /**
     * @custom:scenario The user0 initiates a `deposit` action and user1 validates user0 action after a change of
     * the security deposit value
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user0 at the initialization of the deposit
     * @custom:then We skip validation deadline + 1
     * @custom:and We change the value of the security deposit to SECURITY_DEPOSIT_VALUE / 2
     * @custom:and The protocol returns `SECURITY_DEPOSIT_VALUE` the user1 at the initialization of his deposit
     */
    function test_changeValue_multipleUsers() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();
        uint256 usdnBalanceUser0Before = usdn.balanceOf(address(this));
        uint256 usdnBalanceUser1Before = usdn.balanceOf(USER_1);
        uint64 newSecurityDepositValue = SECURITY_DEPOSIT_VALUE / 2;

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();

        assertSecurityDepositPaid();

        vm.prank(ADMIN);
        protocol.setSecurityDepositValue(newSecurityDepositValue);
        assertEq(
            protocol.getSecurityDepositValue(),
            newSecurityDepositValue,
            "the security deposit value should have changed"
        );

        PreviousActionsData memory previousActionsData = _createPrevActionDataStruct(USER_1, false);

        vm.expectEmit();
        emit SecurityDepositRefunded(address(this), USER_1, SECURITY_DEPOSIT_VALUE);
        vm.prank(USER_1);
        protocol.initiateDeposit{ value: newSecurityDepositValue }(
            1 ether, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, priceData, previousActionsData
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

        assertBalancesEndTwoUsers();

        // we assert that both deposits went through
        assertGt(usdn.balanceOf(address(this)), usdnBalanceUser0Before, "user0 should have received usdn");
        assertGt(usdn.balanceOf(USER_1), usdnBalanceUser1Before, "user1 should have received usdn");
    }

    /* -------------------------------------------------------------------------- */
    /*                         stale pending actions tests                        */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates and validates a `deposit` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The protocol takes the security deposit from the user at the initialization of the deposit
     * @custom:then The protocol returns the security deposit to the user at the validation of the deposit
     */
    function test_refundStaleTransaction() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        PositionId memory posId = _createStalePendingActionHelper();

        assertSecurityDepositPaid();

        wstETH.approve(address(protocol), 1 ether);
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the user should have retrieved his first security deposit from the stale pending action"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the balance of the protocol after the second initialization should have only one security deposit"
        );

        protocol.validateDeposit(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        assertBalancesEnd();
    }

    /**
     * @custom:scenario The user initiates a `deposit` with a stale pending action
     * @custom:given The validator is different than the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the validator
     */
    function test_refundStaleToValidatorInDeposit() public {
        PositionId memory posId = _createStalePendingActionHelper();

        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        vm.prank(USER_1);
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, DISABLE_SHARES_OUT_MIN, USER_1, payable(this), type(uint256).max, priceData, EMPTY_PREVIOUS_DATA
        );

        assertStaleRefundValues();
    }

    /**
     * @custom:scenario The user initiates a `open` with a stale pending action
     * @custom:given The validator is different than the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the validator
     */
    function test_refundStaleToValidatorInOpen() public {
        PositionId memory posId = _createStalePendingActionHelper();
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        vm.startPrank(USER_1);
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        assertStaleRefundValues();
    }

    /**
     * @custom:scenario The user initiates a `open` with a stale pending action
     * @custom:given The validator is equal to the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the user
     */
    function test_refoundToValidatorIsMsgSenderInOpen() public {
        PositionId memory posId = _createStalePendingActionHelper();
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        assertStaleRefundValuesMsgSender();
    }

    /**
     * @custom:scenario The user initiates a `withdrawal` with a stale pending action
     * @custom:given The validator is different than the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the validator
     */
    function test_refundStaleToValidatorInWithdrawal() public {
        PositionId memory posId = _createStalePendingActionHelper();
        vm.startPrank(USER_1);

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateDeposit(payable(USER_1), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        usdn.approve(address(protocol), type(uint256).max);
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            uint128(usdn.balanceOf(USER_1)),
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        vm.stopPrank();

        assertStaleRefundValues();
    }

    /**
     * @custom:scenario The user initiates a `withdrawal` with a stale pending action
     * @custom:given The validator is equal to the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the user
     */
    function test_refoundStaleToMsgSenderInWithdrawal() public {
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateDeposit(payable(this), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        PositionId memory posId = _createStalePendingActionHelper();

        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        usdn.approve(address(protocol), type(uint256).max);
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            uint128(usdn.balanceOf(address(this))),
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        assertEq(
            address(this).balance,
            balanceUser0Before + SECURITY_DEPOSIT_VALUE - SECURITY_DEPOSIT_VALUE,
            "the user 0 should have received the first security deposit and paid the second"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the balance of the protocol after the second initialization should be equal"
        );
    }

    /**
     * @custom:scenario The user initiates a `close` with a stale pending action
     * @custom:given The validator is different than the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the validator
     */
    function test_refundStaleToValidatorInClose() public {
        PositionId memory posId = _createStalePendingActionHelper();

        vm.startPrank(USER_1);

        (, PositionId memory user1PosId) = protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            USER_1,
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        protocol.validateOpenPosition(payable(USER_1), priceData, EMPTY_PREVIOUS_DATA);

        _waitDelay();

        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            user1PosId,
            1 ether,
            DISABLE_MIN_PRICE,
            USER_1,
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );

        vm.stopPrank();

        assertStaleRefundValues();
    }

    /**
     * @custom:scenario The user initiates a `close` with a stale pending action
     * @custom:given The validator is equal to the user
     * @custom:when The action is initiated
     * @custom:then The protocol takes the security deposit from the user
     * @custom:and The protocol returns the security deposit of the stale pending action to the user
     */
    function test_refundStaleToValidatorIsMsgSenderInClose() public {
        PositionId memory posId = _createStalePendingActionHelper();
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        (, PositionId memory user1PosId) = protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            USER_1,
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        protocol.validateOpenPosition(payable(USER_1), priceData, EMPTY_PREVIOUS_DATA);

        _waitDelay();

        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before,) = _getBalances();

        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), posId);
        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            user1PosId,
            1 ether,
            DISABLE_MIN_PRICE,
            USER_1,
            payable(this),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );

        assertStaleRefundValuesMsgSender();
    }

    /* -------------------------------------------------------------------------- */
    /*           validator is a contract with no receive function tests           */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A smart contract with no {receive} function is the validator of a deposit
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The validator tries to validate the deposit
     * @custom:then The transaction reverts with the error `UsdnProtocolEtherRefundFailed`
     */
    function test_RevertWhen_refundSmartContract_noReceive() public {
        (balanceUser0Before, balanceProtocolBefore,,) = _getBalances();

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(receiverContract)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaid();

        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        receiverContract.validateDeposit(address(protocol), priceData, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario A smart contract with no {receive} function is the validator of a `deposit` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The validator tries to validate the deposit
     * @custom:then The transaction reverts with the error `UsdnProtocolEtherRefundFailed`
     * @custom:and We skip the validation deadline + 1
     * @custom:when A user tries to validate the pending action
     * @custom:then The security deposit is refunded to the user and not to the receiver contract
     */
    function test_deposit_refundSmartContract_noReceive() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before, balanceReceiverContractBefore) = _getBalances();

        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            USER_1,
            payable(address(receiverContract)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();
        assertSecurityDepositPaidDummyContract();

        // the dummy contract (validator) does not implement a receive function so we expect a revert
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        receiverContract.validateDeposit(address(protocol), priceData, EMPTY_PREVIOUS_DATA);

        _waitBeforeActionablePendingAction();

        PreviousActionsData memory prevActionsData = _createPrevActionDataStruct(address(this), true);

        // we validate the pending action with the user when the validation deadline has passed
        vm.prank(USER_1);
        protocol.validateActionablePendingActions(prevActionsData, 1);

        // we assert that the security deposit has been refunded to the user1 and not to the receiver contract
        assertBalancesEndDummyContract();
    }

    /**
     * @custom:scenario A smart contract with no {receive} function is the validator of a `withdraw` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The validator tries to validate the deposit
     * @custom:then The transaction reverts with the error `UsdnProtocolEtherRefundFailed`
     * @custom:and We skip the validation deadline + 1
     * @custom:when A user tries to validate the pending action
     * @custom:then The security deposit is refunded to the user and not to the receiver contract
     */
    function test_withdraw_refundSmartContract_noReceive() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before, balanceReceiverContractBefore) = _getBalances();

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        usdn.approve(address(protocol), 1);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(
            1,
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            payable(address(receiverContract)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertSecurityDepositPaidDummyContract();

        // the dummy contract (validator) does not implement a receive function so we expect a revert
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        receiverContract.validateWithdrawal(address(protocol), priceData, EMPTY_PREVIOUS_DATA);

        _waitBeforeActionablePendingAction();

        PreviousActionsData memory prevActionsData = _createPrevActionDataStruct(address(this), true);

        // we validate the pending action with the user when the validation deadline has passed
        vm.prank(USER_1);
        protocol.validateActionablePendingActions(prevActionsData, 1);

        // we assert that the security deposit has been refunded to the user1 and not to the receiver contract
        assertBalancesEndDummyContract();
    }

    /**
     * @custom:scenario A smart contract with no {receive} function is the validator of a `openPosition` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The validator tries to validate the deposit
     * @custom:then The transaction reverts with the error `UsdnProtocolEtherRefundFailed`
     * @custom:and We skip the validation deadline + 1
     * @custom:when A user tries to validate the pending action
     * @custom:then The security deposit is refunded to the user and not to the receiver contract
     */
    function test_openPosition_refundSmartContract_noReceive() public {
        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before, balanceReceiverContractBefore) = _getBalances();

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_1,
            payable(address(receiverContract)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();
        assertSecurityDepositPaidDummyContract();

        // the dummy contract (validator) does not implement a receive function so we expect a revert
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        receiverContract.validateOpenPosition(address(protocol), priceData, EMPTY_PREVIOUS_DATA);

        _waitBeforeActionablePendingAction();

        PreviousActionsData memory prevActionsData = _createPrevActionDataStruct(address(this), true);

        // we validate the pending action with the user when the validation deadline has passed
        vm.prank(USER_1);
        protocol.validateActionablePendingActions(prevActionsData, 1);

        // we assert that the security deposit has been refunded to the user1 and not to the receiver contract
        assertBalancesEndDummyContract();
    }

    /**
     * @custom:scenario A smart contract with no {receive} function is the validator of a `closePosition` action
     * @custom:given The value of the security deposit is `SECURITY_DEPOSIT_VALUE`
     * @custom:when The validator tries to validate the deposit
     * @custom:then The transaction reverts with the error `UsdnProtocolEtherRefundFailed`
     * @custom:and We skip the validation deadline + 1
     * @custom:when A user tries to validate the pending action
     * @custom:then The security deposit is refunded to the user and not to the receiver contract
     */
    function test_closePosition_refundSmartContract_noReceive() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        (balanceUser0Before, balanceProtocolBefore, balanceUser1Before, balanceReceiverContractBefore) = _getBalances();

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            posId,
            1 ether,
            DISABLE_MIN_PRICE,
            USER_1,
            payable(address(receiverContract)),
            type(uint256).max,
            priceData,
            EMPTY_PREVIOUS_DATA,
            ""
        );

        _waitDelay();

        assertSecurityDepositPaidDummyContract();

        // the dummy contract (validator) does not implement a receive function so we expect a revert
        vm.expectRevert(UsdnProtocolEtherRefundFailed.selector);
        receiverContract.validateClosePosition(address(protocol), priceData, EMPTY_PREVIOUS_DATA);

        _waitBeforeActionablePendingAction();

        PreviousActionsData memory prevActionsData = _createPrevActionDataStruct(address(this), true);

        // we validate the pending action with the user when the validation deadline has passed
        vm.prank(USER_1);
        protocol.validateActionablePendingActions(prevActionsData, 1);

        // we assert that the security deposit has been refunded to the user1 and not to the receiver contract
        assertBalancesEndDummyContract();
    }

    /* -------------------------------------------------------------------------- */
    /*                                test helpers                                */
    /* -------------------------------------------------------------------------- */

    function assertStaleRefundValues() public view {
        assertEq(
            address(this).balance,
            balanceUser0Before + SECURITY_DEPOSIT_VALUE,
            "the user 0 should have retrieved his first security deposit from the stale pending action"
        );

        assertEq(
            USER_1.balance,
            balanceUser1Before - SECURITY_DEPOSIT_VALUE,
            "the user 1 shouldn't have retrieved the security deposit from the stale pending action"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the balance of the protocol after the second initialization should be equal"
        );
    }

    function assertStaleRefundValuesMsgSender() public view {
        assertEq(
            address(this).balance, balanceUser0Before, "the user 0 should have the same balance than before all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the balance of the protocol after the second initialization should be equal"
        );
    }

    function assertSecurityDepositPaid() public view {
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the balance of the user after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
    }

    function assertSecurityDepositPaidDummyContract() public view {
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the balance of the user0 after initialization should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore + SECURITY_DEPOSIT_VALUE,
            "the balance of the protocol after initialization should have SECURITY_DEPOSIT_VALUE more"
        );
        assertEq(
            address(USER_1).balance,
            balanceUser1Before,
            "the balance of the user1 after initialization should be the same than before all actions"
        );
        assertEq(
            address(receiverContract).balance,
            balanceReceiverContractBefore,
            "the balance of the `receiverContract` after initialization should be the same than before all actions"
        );
    }

    function assertBalancesEnd() public view {
        assertEq(
            address(this).balance,
            balanceUser0Before,
            "the balance of the user after all actions should be the same than before all actions"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the balance of the protocol after all actions should be the same than before all actions"
        );
    }

    function assertBalancesEndDummyContract() public view {
        assertEq(
            address(this).balance,
            balanceUser0Before - SECURITY_DEPOSIT_VALUE,
            "the balance of the user0 after all actions should have SECURITY_DEPOSIT_VALUE less"
        );
        assertEq(
            address(protocol).balance,
            balanceProtocolBefore,
            "the balance of the protocol after all actions should be the same as before"
        );
        assertEq(
            address(USER_1).balance,
            balanceUser1Before + SECURITY_DEPOSIT_VALUE,
            "the balance of the user1 after all actions should have `SECURITY_DEPOSIT_VALUE` more"
        );
        assertEq(
            address(receiverContract).balance,
            balanceReceiverContractBefore,
            "the balance of the `receiverContract` after all actions should be the same than before"
        );
    }

    function assertBalancesEndTwoUsers() public view {
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
            "the protocol balance after all actions should be the same as a the beginning"
        );
    }

    function assertRefundEthToUser1() public view {
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

    function assertSecurityDepositPaidTwoUsers() public view {
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

    function _getBalances()
        public
        view
        returns (
            uint256 balanceUser0Before_,
            uint256 balanceProtocolBefore_,
            uint256 balanceUser1Before_,
            uint256 balanceReceiverContractBefore_
        )
    {
        return (address(this).balance, address(protocol).balance, USER_1.balance, address(receiverContract).balance);
    }

    function _createPrevActionDataStruct(address user, bool assertValidatorContract)
        internal
        view
        returns (PreviousActionsData memory prevActionsData_)
    {
        (PendingAction[] memory pendingAction, uint128[] memory rawIndices) = protocol.getActionablePendingActions(user);
        bytes[] memory prevPriceData = new bytes[](rawIndices.length);
        prevPriceData[0] = priceData;

        if (assertValidatorContract) {
            assertEq(pendingAction.length, 1, "actions length");
            assertEq(pendingAction[0].to, USER_1, "action `to`");
            assertEq(pendingAction[0].validator, address(receiverContract), "action `validator`");
        }

        prevActionsData_ = PreviousActionsData({ priceData: prevPriceData, rawIndices: rawIndices });
    }

    receive() external payable { }
}

/**
 * @title DummyContract
 * @dev This contract is used to interact with the USDN protocol and does not have a `receive()` function.
 */
contract DummyContract is IUsdnProtocolTypes {
    function validateDeposit(
        address usdnProtocolAddr,
        bytes calldata priceData,
        PreviousActionsData calldata previousData
    ) external {
        IUsdnProtocolImpl(usdnProtocolAddr).validateDeposit(payable(address(this)), priceData, previousData);
    }

    function validateWithdrawal(
        address usdnProtocolAddr,
        bytes calldata priceData,
        PreviousActionsData calldata previousData
    ) external {
        IUsdnProtocolImpl(usdnProtocolAddr).validateWithdrawal(payable(address(this)), priceData, previousData);
    }

    function validateOpenPosition(
        address usdnProtocolAddr,
        bytes calldata priceData,
        PreviousActionsData calldata previousData
    ) external {
        IUsdnProtocolImpl(usdnProtocolAddr).validateOpenPosition(payable(address(this)), priceData, previousData);
    }

    function validateClosePosition(
        address usdnProtocolAddr,
        bytes calldata priceData,
        PreviousActionsData calldata previousData
    ) external {
        IUsdnProtocolImpl(usdnProtocolAddr).validateClosePosition(payable(address(this)), priceData, previousData);
    }
}
