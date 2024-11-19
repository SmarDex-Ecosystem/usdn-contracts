// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2, USER_3, USER_4 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The functions handling the pending actions queue
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolPending is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Get the actionable pending actions
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadlines have elapsed
     * @custom:when The actionable pending actions are requested
     * @custom:then The pending actions are returned for both periods
     */
    function test_getActionablePendingActions() public {
        // there should be no pending action at this stage
        (PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "pending action before initiate");
        // initiate deposit
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, 2000 ether);
        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        // the pending action is not yet actionable until the low latency validation deadline
        vm.warp(pending.timestamp + protocol.getLowLatencyValidatorDeadline());
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "pending action after initiate");
        // the pending action is actionable after the low latency validation deadline
        vm.warp(pending.timestamp + protocol.getLowLatencyValidatorDeadline() + 1);
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 1, "actions length");
        assertEq(actions[0].to, address(this), "action to");
        assertEq(actions[0].validator, address(this), "action validator");
        assertEq(rawIndices[0], 0, "raw index");
        // the pending action is not actionable anymore after the low latency delay
        vm.warp(pending.timestamp + oracleMiddleware.getLowLatencyDelay() + 1);
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "pending action after low latency delay");
        // the pending action is again actionable after the on-chain validation deadline
        vm.warp(pending.timestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1);
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 1, "actions length");
    }

    /**
     * @custom:scenario Get the first actionable pending action
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadlines have elapsed
     * @custom:when The first actionable pending action is requested
     * @custom:then The pending action is returned for both periods
     */
    function test_internalGetActionablePendingAction() public {
        // there should be no pending action at this stage
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "pending action before initiate");
        // initiate deposit
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, 2000 ether);
        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        // the pending action is not yet actionable until the low latency validation deadline
        vm.warp(pending.timestamp + protocol.getLowLatencyValidatorDeadline());
        (action, rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "pending action after initiate");
        // the pending action is actionable after the low latency validation deadline
        vm.warp(pending.timestamp + protocol.getLowLatencyValidatorDeadline() + 1);
        (action, rawIndex) = protocol.i_getActionablePendingAction();
        assertEq(action.to, address(this), "action to");
        assertEq(action.validator, address(this), "action validator");
        assertEq(rawIndex, 0, "raw index");
        // the pending action is not actionable anymore after the low latency delay
        vm.warp(pending.timestamp + oracleMiddleware.getLowLatencyDelay() + 1);
        (action, rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "pending action after low latency delay");
        // the pending action is again actionable after the on-chain validation deadline
        vm.warp(pending.timestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1);
        (action, rawIndex) = protocol.i_getActionablePendingAction();
        assertEq(action.to, address(this), "action to");
    }

    /**
     * @dev Set up 3 user positions in long and artificially remove the pending actions for user 2 and 1, leaving the
     * first item in the queue being zero-valued.
     */
    function _setupSparsePendingActionsQueue() internal {
        // Setup 3 pending actions
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: 1000 ether,
                price: 2000 ether
            })
        );
        setUpUserPositionInLong(
            OpenParams({
                user: USER_2,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: 1000 ether,
                price: 2000 ether
            })
        );
        setUpUserPositionInLong(
            OpenParams({
                user: USER_3,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: 1000 ether,
                price: 2000 ether
            })
        );
        // Simulate the second item in the queue being empty (sets it to zero values)
        protocol.removePendingAction(1, USER_2);
        // Simulate the first item in the queue being empty
        // This will pop the first item, but leave the second empty
        protocol.removePendingAction(0, USER_1);
    }

    /**
     * @custom:scenario Get the actionable pending actions when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The actionable pending actions are requested
     * @custom:then The third pending action is returned
     */
    function test_getActionablePendingActionsSparse() public {
        _setupSparsePendingActionsQueue();

        // Wait
        _waitBeforeActionablePendingAction();

        (PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 1, "actions length");
        assertEq(actions[0].to, USER_3, "to");
        assertEq(actions[0].validator, USER_3, "validator");
        assertEq(rawIndices[0], 2, "raw index");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is sparse
     * @custom:given 3 users have initiated a deposit
     * @custom:and The first and second pending actions have been manually removed from the queue
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_internalGetActionablePendingActionSparse() public {
        _setupSparsePendingActionsQueue();

        // Wait
        _waitBeforeActionablePendingAction();

        (PendingAction memory action, uint128 rawIndex) = protocol.i_getActionablePendingAction();
        assertTrue(action.to == USER_3, "to");
        assertTrue(action.validator == USER_3, "validator");
        assertEq(rawIndex, 2, "raw index");
    }

    /**
     * @custom:scenario Get the actionable pending actions when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The actionable pending actions are requested
     * @custom:then No actionable pending action is returned
     */
    function test_getActionablePendingActionEmpty() public view {
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "empty list");
    }

    /**
     * @custom:scenario Get the first actionable pending action when the queue is empty
     * @custom:given The queue is empty
     * @custom:when The first actionable pending action is requested
     * @custom:then No actionable pending action is returned
     */
    function test_internalGetActionablePendingActionEmpty() public {
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getActionablePendingAction();
        assertEq(action.to, address(0), "action to");
        assertEq(action.validator, address(0), "action validator");
        assertEq(rawIndex, 0, "raw index");
    }

    /**
     * @custom:scenario User who didn't validate their tx after their exclusivity and call `getActionablePendingAction`
     * @custom:background When a user have their own action in the first position in the queue and it's actionable by
     * someone else, they should retrieve the next item in the queue at the moment of validating their own action.
     * This is because they will remove their own action from the queue before attempting to validate the next item in
     * the queue, and it would revert if they provided the price data for their own actionable pending action.
     * @custom:given The user has initiated a long and waited the validation deadline duration
     * @custom:and Their transaction is still the first in the queue
     * @custom:when They call `getActionablePendingAction`
     * @custom:then Their pending action in the queue is skipped and not returned
     */
    function test_getActionablePendingActionSameUser() public {
        // initiate long
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: 1000 ether,
                price: 2000 ether
            })
        );
        // the pending action is actionable after the validation deadline
        _waitBeforeActionablePendingAction();
        (PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 1, "actions length");
        assertEq(actions[0].to, address(this), "action to");
        assertEq(actions[0].validator, address(this), "action validator");
        assertEq(rawIndices[0], 0, "action rawIndex");
        // but if the user himself calls the function, the action should not be returned
        (actions, rawIndices) = protocol.getActionablePendingActions(address(this), 0);
        assertEq(actions.length, 0, "no action");
    }

    /**
     * @custom:scenario Validate a user's pending position which is actionable at the same time as another user's
     * pending action.
     * @custom:given Two users have initiated deposits
     * @custom:and The validation deadline has elapsed for both of them
     * @custom:when The second user validates their pending position
     * @custom:then Both positions are validated
     */
    function test_twoPending() public {
        uint128 price1 = 2000 ether;
        uint128 price2 = 2100 ether;
        // Setup 2 pending actions
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: 1000 ether,
                price: price1
            })
        );
        setUpUserPositionInLong(
            OpenParams({
                user: USER_2,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: 1000 ether,
                price: price2
            })
        );

        // Wait
        _waitBeforeActionablePendingAction();

        // Second user tries to validate their action
        vm.prank(USER_2);
        bytes[] memory previousData = new bytes[](1);
        previousData[0] = abi.encode(price1);
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;
        protocol.validateOpenPosition(USER_2, abi.encode(price2), PreviousActionsData(previousData, rawIndices));
        // No more pending action
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "no action");
        (PendingAction memory action,) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "no action (internal)");
    }

    /**
     * @custom:scenario Two actionable pending actions are validated by two other users in the same block
     * @custom:given Two users have initiated deposits and the deadline has elapsed
     * @custom:when Two other users validate the pending actions in the same block
     * @custom:then Both positions are validated and there are no reverts
     */
    function test_twoUsersValidatingInSameBlock() public {
        uint128 price1 = 2000 ether;
        uint128 price2 = 2100 ether;

        // Setup 2 pending actions
        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, 1 ether, price1);
        setUpUserPositionInVault(USER_2, ProtocolAction.InitiateDeposit, 1 ether, price2);

        // Wait
        _waitBeforeActionablePendingAction();

        // Two other users want to now enter the protocol
        wstETH.mintAndApprove(USER_3, 100_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_4, 100_000 ether, address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_3, 100_000 ether, address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_4, 100_000 ether, address(protocol), type(uint256).max);
        (PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 2, "actions length");
        bytes[] memory previousPriceData = new bytes[](actions.length);
        previousPriceData[0] = abi.encode(price1);
        previousPriceData[1] = abi.encode(price2);
        PreviousActionsData memory previousActionsData =
            PreviousActionsData({ priceData: previousPriceData, rawIndices: rawIndices });
        vm.prank(USER_3);
        protocol.initiateDeposit(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            USER_3,
            USER_3,
            type(uint256).max,
            abi.encode(2200 ether),
            previousActionsData
        );
        vm.prank(USER_4);
        protocol.initiateDeposit(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            USER_4,
            USER_4,
            type(uint256).max,
            abi.encode(2200 ether),
            previousActionsData
        );

        // They should have validated both pending actions
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "final actions length");
    }

    /**
     * @custom:scenario There is a pending action in the queue but the first ones are not actionable
     * @custom:given A queue with three pending actions which are not actionable (low-latency period has elapsed)
     * @custom:and A fourth pending action which is actionable with low-latency oracle
     * @custom:when The first actionable pending action is retrieved
     * @custom:then The fourth pending action is returned
     * @custom:when The list of actionable pending actions is retrieved
     * @custom:then The fourth pending action is the only one returned
     * @custom:when We wait until all actions are actionable again
     * @custom:then All four pending actions are returned
     */
    function test_actionablePendingActionInSecondPeriod() public {
        // low latency oracle is down and 3 pending actions are created
        uint40 timestamp = uint40(block.timestamp);
        DepositPendingAction memory pendingDeposit = DepositPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: timestamp,
            feeBps: 0,
            to: USER_1,
            validator: USER_1,
            securityDepositValue: 0,
            amount: 1 ether,
            _unused: 0,
            assetPrice: 2000 ether,
            totalExpo: 20 ether,
            balanceVault: 20 ether,
            balanceLong: 20 ether,
            usdnTotalShares: 100e36
        });
        protocol.i_addPendingAction(USER_1, protocol.i_convertDepositPendingAction(pendingDeposit));
        pendingDeposit.to = USER_2;
        pendingDeposit.validator = USER_2;
        pendingDeposit.timestamp = timestamp + 1 minutes;
        protocol.i_addPendingAction(USER_2, protocol.i_convertDepositPendingAction(pendingDeposit));
        pendingDeposit.to = USER_3;
        pendingDeposit.validator = USER_3;
        pendingDeposit.timestamp = timestamp + 2 minutes;
        protocol.i_addPendingAction(USER_3, protocol.i_convertDepositPendingAction(pendingDeposit));
        // wait for the low latency period to end for all 3 actions, they are not actionable anymore
        vm.warp(pendingDeposit.timestamp + oracleMiddleware.getLowLatencyDelay() + 1);
        (PendingAction memory action,) = protocol.i_getActionablePendingAction();
        assertTrue(action.action == ProtocolAction.None, "no action");
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 0, "actions length after 3 actions exceed low latency period");
        // add a fourth pending action
        pendingDeposit.to = USER_4;
        pendingDeposit.validator = USER_4;
        pendingDeposit.timestamp = uint40(block.timestamp);
        protocol.i_addPendingAction(USER_4, protocol.i_convertDepositPendingAction(pendingDeposit));
        // wait until it is actionable
        vm.warp(pendingDeposit.timestamp + protocol.getLowLatencyValidatorDeadline() + 1);
        // the fourth pending action is now actionable (the others are not yet)
        (action,) = protocol.i_getActionablePendingAction();
        assertEq(action.validator, USER_4, "fourth action");
        (actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 1, "actions length after fourth action becomes actionable");
        // wait for the first action to become actionable again
        vm.warp(timestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1);
        // the first action is now actionable
        (action,) = protocol.i_getActionablePendingAction();
        assertEq(action.validator, USER_1, "first action");
        (actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 1, "actions length after first action becomes actionable again");
        // wait until all actions are actionable
        vm.warp(
            pendingDeposit.timestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline()
                + 1
        );
        (actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 4, "actions length when all are actionable");
    }

    /**
     * @custom:scenario There are two pending actions in the queue but they are disjoint
     * @custom:given A queue with one pending action which is actionable with on-chain oracle
     * @custom:and A second pending action which is not actionable
     * @custom:and A third pending action which is actionable with low-latency oracle
     * @custom:when The first actionable pending action is retrieved
     * @custom:then The first pending action is returned
     * @custom:when The list of actionable pending actions is retrieved
     * @custom:then The first and third pending actions are returned, with an empty element in the middle
     */
    function test_actionablePendingActionsInBothPeriods() public {
        uint40 timestamp = uint40(block.timestamp);
        DepositPendingAction memory pendingDeposit = DepositPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: timestamp,
            _unused: 0,
            to: USER_1,
            validator: USER_1,
            securityDepositValue: 0,
            feeBps: 0,
            amount: 1 ether,
            assetPrice: 2000 ether,
            totalExpo: 20 ether,
            balanceVault: 20 ether,
            balanceLong: 20 ether,
            usdnTotalShares: 100e36
        });
        protocol.i_addPendingAction(USER_1, protocol.i_convertDepositPendingAction(pendingDeposit));
        pendingDeposit.to = USER_2;
        pendingDeposit.validator = USER_2;
        pendingDeposit.timestamp = uint40(timestamp + protocol.getOnChainValidatorDeadline() / 2);
        protocol.i_addPendingAction(USER_2, protocol.i_convertDepositPendingAction(pendingDeposit));
        pendingDeposit.to = USER_3;
        pendingDeposit.validator = USER_3;
        pendingDeposit.timestamp = uint40(timestamp + protocol.getOnChainValidatorDeadline() + 1);
        protocol.i_addPendingAction(USER_3, protocol.i_convertDepositPendingAction(pendingDeposit));
        // wait until the first and third are actionable
        vm.warp(timestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1);
        // the first and third actions are now actionable
        (PendingAction memory action,) = protocol.i_getActionablePendingAction();
        assertEq(action.validator, USER_1, "first action");
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0), 0);
        assertEq(actions.length, 3, "actions length after two actions are actionable");
        assertEq(actions[0].validator, USER_1, "first action");
        assertEq(actions[1].validator, address(0), "second action (empty)");
        assertEq(actions[2].validator, USER_3, "third action");
    }

    /**
     * @custom:scenario Convert an untyped pending action into a deposit pending action
     * @custom:given An untyped `PendingAction`
     * @custom:when The action is converted to a `DepositPendingAction` and back into a `PendingAction`
     * @custom:then The original and the converted `PendingAction` are equal
     */
    function test_internalConvertDepositPendingAction() public view {
        PendingAction memory action = PendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            var0: 0, // must be zero because unused
            to: address(this),
            validator: address(this),
            securityDepositValue: 2424,
            var1: 0, // must be zero because unused
            var2: 42,
            var3: 69,
            var4: 420,
            var5: 1337,
            var6: 9000,
            var7: 23
        });
        DepositPendingAction memory depositAction = protocol.i_toDepositPendingAction(action);
        assertTrue(depositAction.action == action.action, "action action");
        assertEq(depositAction.timestamp, action.timestamp, "action timestamp");
        assertEq(depositAction._unused, action.var0, "action var0");
        assertEq(depositAction.to, action.to, "action to");
        assertEq(depositAction.validator, action.validator, "action validator");
        assertEq(depositAction.securityDepositValue, action.securityDepositValue, "action security deposit value");
        assertEq(depositAction.feeBps, uint24(action.var1), "action fee");
        assertEq(depositAction.amount, action.var2, "action amount");
        assertEq(depositAction.assetPrice, action.var3, "action price");
        assertEq(depositAction.totalExpo, action.var4, "action expo");
        assertEq(depositAction.balanceVault, action.var5, "action balance vault");
        assertEq(depositAction.balanceLong, action.var6, "action balance long");
        assertEq(depositAction.usdnTotalShares, action.var7, "action total shares");
        PendingAction memory result = protocol.i_convertDepositPendingAction(depositAction);
        _assertActionsEqual(action, result, "deposit pending action conversion");
    }

    /**
     * @custom:scenario Convert an untyped pending action into a withdrawal pending action
     * @custom:given An untyped `PendingAction`
     * @custom:when The action is converted to a `WithdrawalPendingAction` and back into a `PendingAction`
     * @custom:then The original and the converted `PendingAction` are equal
     */
    function test_internalConvertWithdrawalPendingAction() public view {
        PendingAction memory action = PendingAction({
            action: ProtocolAction.ValidateWithdrawal,
            timestamp: uint40(block.timestamp),
            var0: 0, // must be zero because unused
            to: address(this),
            validator: address(this),
            securityDepositValue: 2424,
            var1: 125,
            var2: 42,
            var3: 69,
            var4: 420,
            var5: 1337,
            var6: 9000,
            var7: 23
        });
        WithdrawalPendingAction memory withdrawalAction = protocol.i_toWithdrawalPendingAction(action);
        assertTrue(withdrawalAction.action == action.action, "action action");
        assertEq(withdrawalAction.timestamp, action.timestamp, "action timestamp");
        assertEq(withdrawalAction.feeBps, action.var0, "action feeBps");
        assertEq(withdrawalAction.to, action.to, "action to");
        assertEq(withdrawalAction.validator, action.validator, "action validator");
        assertEq(withdrawalAction.securityDepositValue, action.securityDepositValue, "action security deposit value");
        assertEq(int24(withdrawalAction.sharesLSB), action.var1, "action shares LSB");
        assertEq(withdrawalAction.sharesMSB, action.var2, "action shares MSB");
        assertEq(withdrawalAction.assetPrice, action.var3, "action price");
        assertEq(withdrawalAction.totalExpo, action.var4, "action expo");
        assertEq(withdrawalAction.balanceVault, action.var5, "action balance vault");
        assertEq(withdrawalAction.balanceLong, action.var6, "action balance long");
        assertEq(withdrawalAction.usdnTotalShares, action.var7, "action total supply");
        PendingAction memory result = protocol.i_convertWithdrawalPendingAction(withdrawalAction);
        _assertActionsEqual(action, result, "withdrawal pending action conversion");
    }

    /**
     * @custom:scenario Convert an untyped pending action into a long pending action
     * @custom:given An untyped `PendingAction`
     * @custom:when The action is converted to a `LongPendingAction` and back into a `PendingAction`
     * @custom:then The original and the converted `PendingAction` are equal
     */
    function test_internalConvertLongPendingAction() public view {
        PendingAction memory action = PendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            var0: 0, // must be zero because unused
            to: address(this),
            validator: address(this),
            securityDepositValue: 2424,
            var1: 2398,
            var2: 42,
            var3: 69,
            var4: 420,
            var5: 1337,
            var6: 9000,
            var7: 23
        });
        LongPendingAction memory longAction = protocol.i_toLongPendingAction(action);
        assertTrue(longAction.action == action.action, "action action");
        assertEq(longAction.timestamp, action.timestamp, "action timestamp");
        assertEq(longAction.closeLiqPenalty, action.var0, "action liqPenalty");
        assertEq(longAction.to, action.to, "action to");
        assertEq(longAction.validator, action.validator, "action validator");
        assertEq(longAction.securityDepositValue, action.securityDepositValue, "action security deposit value");
        assertEq(longAction.tick, action.var1, "action tick");
        assertEq(longAction.closeAmount, action.var2, "action amount");
        assertEq(longAction.closePosTotalExpo, action.var3, "action pos total expo");
        assertEq(longAction.tickVersion, action.var4, "action version");
        assertEq(longAction.index, action.var5, "action index");
        assertEq(longAction.liqMultiplier, action.var6, "action liq multiplier");
        assertEq(longAction.closeBoundedPositionValue, action.var7, "action pos value");
        PendingAction memory result = protocol.i_convertLongPendingAction(longAction);
        _assertActionsEqual(action, result, "long pending action conversion");
    }
}
