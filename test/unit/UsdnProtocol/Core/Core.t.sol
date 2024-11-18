// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { DoubleEndedQueue } from "../../../../src/libraries/DoubleEndedQueue.sol";

/**
 * @custom:feature The functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized at equilibrium
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Check return values of the `funding` function
     * @custom:when The timestamp is the same as the initial timestamp
     * @custom:then The funding should be 0
     * @custom:and The funding rate should be unaffected
     * @custom:and The long expo should be as expected
     */
    function test_funding() public view {
        int256 longExpo = int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong());
        (int256 funding, int256 fundingPerDay, int256 oldLongExpo) = protocol.funding(uint128(params.initialTimestamp));
        assertEq(funding, 0, "funding should be 0 if no time has passed");
        assertEq(fundingPerDay, protocol.getEMA(), "funding rate should be unaffected by time");
        assertEq(oldLongExpo, longExpo, "longExpo if no time has passed");
    }

    /**
     * @custom:scenario Calling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(uint128(params.initialTimestamp) - 1);
    }

    /**
     * @custom:scenario The long position's value is equal to the long side available balance
     * @custom:given No time has elapsed since the initialization
     * @custom:and The price of the asset is equal to the initial price
     * @custom:then The long side available balance is equal to the first position value
     * @dev Due to imprecision in the calculations, there are in practice a few wei of difference, but always in favor
     * of the protocol (see fuzzing tests)
     */
    function test_longAssetAvailable() public view {
        // calculate the value of the deployer's long position
        int24 tick = protocol.getHighestPopulatedTick();
        uint128 longLiqPrice =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(tick, protocol.getLiquidationPenalty()));

        (Position memory firstPos,) = protocol.getLongPosition(PositionId(tick, 0, 0));

        int256 longPosValue = protocol.i_positionValue(firstPos.totalExpo, params.initialPrice, longLiqPrice);

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(protocol.i_longAssetAvailable(params.initialPrice), longPosValue, "long balance");
    }

    /**
     * @custom:scenario EMA updated correctly with negative funding
     * @custom:given The funding rate is negative
     * @custom:when The next action happens just before the EMA period has elapsed
     * @custom:then The new EMA should almost be equal to the funding rate
     */
    function test_updateEma_negFunding() public {
        // we create a deposit to have a negative funding
        bytes memory priceData = abi.encode(params.initialPrice);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 10 ether, params.initialPrice);

        // skip almost the entirety of the EMA period
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.mockLiquidate(priceData);

        int256 lastFundingPerDay = protocol.getLastFundingPerDay();
        assertLt(lastFundingPerDay, 0, "funding should be negative for the elapsed period");

        // within 0.002%
        assertApproxEqRel(
            protocol.getEMA(), lastFundingPerDay, 0.00002 ether, "EMA should be approx equal to the last funding"
        );
    }

    /**
     * @custom:scenario EMA updated correctly with positive funding
     * @custom:given The funding rate is positive
     * @custom:when The next action happens just before the EMA period has elapsed
     * @custom:then The new EMA should almost be equal to the funding rate
     */
    function test_updateEma_posFunding() public {
        // we create a long to have a positive funding
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 200 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        // skip almost the entirety of the EMA period
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.mockLiquidate(abi.encode(params.initialPrice));

        int256 lastFundingPerDay = protocol.getLastFundingPerDay();
        assertGt(lastFundingPerDay, 0, "funding should be positive for the elapsed period");

        // within 0.002%
        assertApproxEqRel(
            protocol.getEMA(), lastFundingPerDay, 0.00002 ether, "EMA should be approx equal to the last funding"
        );
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:given 60 seconds have elapsed since the last update timestamp
     * @custom:when long and vault expos are equal
     * @custom:then funding rate should be equal to EMA
     * @custom:then funding should be as expected
     */
    function test_fundingWhenEqualExpo() public view {
        int256 vaultTradingExpo = protocol.i_vaultAssetAvailable(params.initialPrice);

        assertEq(
            int256(protocol.getLongTradingExpo(params.initialPrice)),
            vaultTradingExpo,
            "long and vault expos should be equal"
        );

        int256 EMA = protocol.getEMA();
        (int256 funding, int256 fundingPerDay, int256 oldLongExpo) =
            protocol.funding(uint128(protocol.getLastUpdateTimestamp() + 60));
        assertEq(fundingPerDay, EMA, "funding rate should be equal to EMA");
        assertEq(funding, EMA * 60 / 1 days, "funding should be as expected");
        assertEq(
            oldLongExpo,
            int256(protocol.getTotalExpo() - protocol.getBalanceLong()),
            "old long expo should be the same as last update"
        );
    }

    /**
     * @custom:scenario No protocol actions during a greater period than the EMA period
     * @custom:given a non-zero funding
     * @custom:and no actions for a period greater than the EMA period
     * @custom:then EMA should be equal to the last funding
     */
    function test_updateEma_whenTimeGtEMAPeriod() public {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        bytes memory priceData = abi.encode(params.initialPrice);
        // we skip 1 day and call liquidate() to have a non-zero funding
        skip(1 days);
        protocol.mockLiquidate(priceData);

        int256 lastFundingPerDay = protocol.getLastFundingPerDay();
        skip(protocol.getEMAPeriod() + 1);
        // we call liquidate() to update the EMA
        protocol.mockLiquidate(priceData);

        assertEq(protocol.getEMA(), lastFundingPerDay, "EMA should be equal to last funding rate");
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when the long expo is negative
     * @custom:and the vault expo is zero
     * @custom:then fund should be equal to -fundingSF + EMA
     */
    function test_funding_NegLong_ZeroVault() public {
        vm.skip(true); // This case is not realistic anymore with the new liquidation multiplier calculations

        skip(1 hours);
        uint128 price = params.initialPrice;
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1000 ether,
                desiredLiqPrice: price * 90 / 100,
                price: price
            })
        );

        skip(1 hours);
        protocol.mockLiquidate(abi.encode(price / 100));
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));

        assertEq(
            fundingPerDay,
            -int256(fundingSF * 10 ** (protocol.FUNDING_RATE_DECIMALS() - protocol.FUNDING_SF_DECIMALS())) + EMA,
            "funding should be equal to -fundingSF + EMA"
        );
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when the long expo is positive
     * @custom:and the vault expo is zero
     * @custom:then fund should be equal to fundingSF + EMA
     */
    function test_funding_PosLong_ZeroVault() public {
        skip(1 hours);
        uint128 price = params.initialPrice;
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1000 ether,
                desiredLiqPrice: price * 90 / 100,
                price: price
            })
        );

        skip(1 hours);
        protocol.mockLiquidate(abi.encode(price * 100));
        assertGt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be positive");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));

        assertEq(
            fundingPerDay,
            int256(fundingSF * 10 ** (protocol.FUNDING_RATE_DECIMALS() - protocol.FUNDING_SF_DECIMALS())) + EMA,
            "funding should be equal to fundingSF + EMA"
        );
    }

    /**
     * @custom:scenario longAssetAvailableWithFunding calculation
     * @custom:when the funding is positive
     * @custom:then return value should be equal to the long balance
     */
    function test_longAssetAvailableWithFunding_posFund() public {
        skip(1 hours);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: price * 90 / 100,
                price: price
            })
        );
        skip(30);

        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));
        assertGt(fundingPerDay, 0, "funding rate should be positive");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        uint256 available = protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.mockLiquidate(priceData);
        assertEq(available, protocol.getBalanceLong(), "long balance != available");
    }

    /**
     * @custom:scenario longAssetAvailableWithFunding returns the highest possible value
     * @custom:when The funding is negative
     * @custom:then Return value should be equal to the min trading expo
     * @custom:and A higher timestamp does not change the returned value
     */
    function test_longAssetAvailableIsCappedByMinTradingExpo() public {
        skip(1 hours);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 100 ether, price);
        skip(30 days);

        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));
        assertLt(fundingPerDay, 0, "funding rate should be negative");

        uint256 available = protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp));

        uint256 minTradingExpo =
            protocol.getTotalExpo() * (BPS_DIVISOR - protocol.MIN_LONG_TRADING_EXPO_BPS()) / BPS_DIVISOR;
        assertEq(available, minTradingExpo, "the long balance should be equal to the min trading expo");

        // check that a higher timestamp does not increase the amount available
        uint256 availableLater = protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp) + 30 days);
        assertEq(available, availableLater, "the available assets should not have changed");
    }

    /**
     * @custom:scenario longAssetAvailableWithFunding calculation
     * @custom:when the funding is negative
     * @custom:then return value should be equal to the long balance
     */
    function test_longAssetAvailableWithFunding_negFund() public {
        uint128 price = DEFAULT_PARAMS.initialPrice;
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 10 ether, price);
        skip(1 hours);

        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));
        assertLt(fundingPerDay, 0, "funding rate should be negative");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        uint256 available = protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.mockLiquidate(abi.encode(price));

        assertEq(available, protocol.getBalanceLong(), "long balance != available");
    }

    /**
     * @custom:scenario Calling the `longAssetAvailableWithFunding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_longAssetAvailableWithFunding_pastTimestamp() public {
        uint128 ts = protocol.getLastUpdateTimestamp();
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.longAssetAvailableWithFunding(0, ts - 1);
    }

    /**
     * @custom:scenario vaultAssetAvailableWithFunding calculation
     * @custom:when the funding is negative
     * @custom:then return value should be equal to the vault balance
     */
    function test_vaultAssetAvailableWithFunding_negFund() public {
        uint128 price = DEFAULT_PARAMS.initialPrice;
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 10 ether, price);
        skip(1 hours);

        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));
        assertLt(fundingPerDay, 0, "funding rate should be negative");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        uint256 available = protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.mockLiquidate(abi.encode(price));

        assertEq(available, protocol.getBalanceVault(), "vault balance != available");
    }

    /**
     * @custom:scenario vaultAssetAvailableWithFunding calculation
     * @custom:when the funding is positive
     * @custom:then return value should be equal to the vault balance
     */
    function test_vaultAssetAvailableWithFunding_posFund() public {
        skip(1 hours);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: price * 90 / 100,
                price: price
            })
        );
        skip(30);

        (, int256 fundingPerDay,) = protocol.funding(uint128(block.timestamp));
        assertGt(fundingPerDay, 0, "funding rate should be positive");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        uint256 available = protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state

        protocol.mockLiquidate(priceData);
        assertEq(available, protocol.getBalanceVault(), "vault balance != available");
    }

    /**
     * @custom:scenario Calling the `vaultAssetAvailableWithFunding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_vaultAssetAvailableWithFunding_pastTimestamp() public {
        uint128 ts = protocol.getLastUpdateTimestamp();
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.vaultAssetAvailableWithFunding(0, ts - 1);
    }

    /**
     * @custom:scenario The `getPendingAction` function returns an empty pending action when there is none
     * @custom:given There is no pending action for this user
     * @custom:when getPendingAction is called
     * @custom:then it returns an empty action and 0 as the rawIndex
     */
    function test_getPendingActionWithoutPendingAction() public view {
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.None, "action should be None");
        assertEq(action.validator, address(0), "user should be empty");
        assertEq(action.to, address(0), "to should be empty");
        assertEq(rawIndex, 0, "rawIndex should be 0");
    }

    /**
     * @custom:scenario The `getPendingAction` function returns the action when there is one
     * @custom:given There is a pending action for this user
     * @custom:when getPendingAction is called
     * @custom:then The function should return the action and the rawIndex
     */
    function test_getPendingAction() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: 1 ether,
                desiredLiqPrice: 2000 ether / 2,
                price: 2000 ether
            })
        );
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.ValidateClosePosition, "action should be ValidateClosePosition");
        assertEq(action.to, address(this), "to should be this contract");
        assertEq(action.validator, address(this), "validator should be this contract");
        assertEq(rawIndex, 1, "rawIndex should be 1");
    }

    /**
     * @custom:scenario The `getPendingActionOrRevert` function return the expected action
     * @custom:given There is a pending action for this user
     * @custom:when getPendingActionOrRevert is called
     * @custom:then The function should return the action and the rawIndex
     */
    function test_getPendingActionOrRevert() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: 1 ether,
                desiredLiqPrice: 2000 ether / 2,
                price: 2000 ether
            })
        );
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingActionOrRevert(address(this));
        assertTrue(action.action == ProtocolAction.ValidateClosePosition, "action should be ValidateClosePosition");
        assertEq(action.to, address(this), "to should be this contract");
        assertEq(action.validator, address(this), "validator should be this contract");
        assertEq(rawIndex, 1, "rawIndex should be 1");
    }

    /**
     * @custom:scenario The `getPendingActionOrRevert` function revert when there are no pending actions
     * @custom:given There is no pending action for this user
     * @custom:when getPendingActionOrRevert is called
     * @custom:then The protocol reverts with `UsdnProtocolNoPendingAction`
     */
    function test_RevertWhen_getPendingActionOrRevertWithoutPendingAction() public {
        vm.expectRevert(UsdnProtocolNoPendingAction.selector);
        protocol.i_getPendingActionOrRevert(address(this));
    }

    /**
     * @custom:scenario The `addPendingAction` function revert when there are multiple pending actions
     * @custom:given There is a pending action for this user
     * @custom:when addPendingAction is called
     * @custom:then The protocol reverts with `UsdnProtocolPendingAction`
     */
    function test_RevertWhen_addPendingActionAlreadyHavePendingAction() public {
        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            var0: 0,
            to: address(this),
            validator: address(this),
            securityDepositValue: 0.1 ether,
            var1: 0,
            var2: 0,
            var3: 0,
            var4: 0,
            var5: 0,
            var6: 0,
            var7: 0
        });
        protocol.i_addPendingAction(address(this), pendingAction);

        vm.expectRevert(UsdnProtocolPendingAction.selector);
        protocol.i_addPendingAction(address(this), pendingAction);
    }

    /**
     * @custom:scenario The `addPendingAction` function return the security deposit value and save the action
     * @custom:given There is a pending action that can be deleted for this user
     * @custom:when addPendingAction is called
     * @custom:then Return the security deposit value and save the expected action
     */
    function test_addPendingAction() public {
        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            var0: 0,
            to: address(this),
            validator: address(this),
            securityDepositValue: 0.01 ether,
            var1: 0,
            var2: 0,
            var3: 0,
            var4: 1,
            var5: 0,
            var6: 0,
            var7: 0
        });
        protocol.i_addPendingAction(address(this), pendingAction);
        _waitDelay();

        (, uint128 rawIndexBefore) = protocol.i_getPendingAction(address(this));

        uint256 securityDepositValue = protocol.i_addPendingAction(address(this), pendingAction);

        (PendingAction memory actionSaved, uint128 rawIndexAfter) = protocol.i_getPendingAction(address(this));

        assertEq(securityDepositValue, 0.01 ether, "securityDepositValue should be 0.01 ether");
        assertEq(rawIndexBefore + 1, rawIndexAfter, "rawIndex should be incremented by 1");
        assertTrue(actionSaved.action == pendingAction.action, "action saved(action)");
        assertEq(actionSaved.timestamp, pendingAction.timestamp, "action saved(timestamp)");
        assertEq(actionSaved.to, pendingAction.to, "action saved(to)");
        assertEq(actionSaved.validator, pendingAction.validator, "action saved(validator)");
        assertEq(
            actionSaved.securityDepositValue, pendingAction.securityDepositValue, "action saved(securityDepositValue)"
        );
        assertEq(actionSaved.var1, pendingAction.var1, "action saved(var1)");
        assertEq(actionSaved.var2, pendingAction.var2, "action saved(var2)");
        assertEq(actionSaved.var3, pendingAction.var3, "action saved(var3)");
        assertEq(actionSaved.var4, pendingAction.var4, "action saved(var4)");
        assertEq(actionSaved.var5, pendingAction.var5, "action saved(var5)");
        assertEq(actionSaved.var6, pendingAction.var6, "action saved(var6)");
        assertEq(actionSaved.var7, pendingAction.var7, "action saved(var7)");
    }

    /**
     * @custom:scenario The `clearPendingAction` function revert when the queue is empty
     * @custom:given A protocol without any pending action
     * @custom:when clearPendingAction is called
     * @custom:then The protocol reverts with `QueueEmpty`
     */
    function test_RevertWhen_clearPendingActionWithoutPendingAction() public {
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        protocol.i_clearPendingAction(address(this), 0);
    }

    /**
     * @custom:scenario The `clearPendingAction` function delete the pending action
     * @custom:given A protocol with a pending action for a user
     * @custom:when clearPendingAction is called
     * @custom:then The pending action should be deleted
     */
    function test_clearPendingAction() public {
        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            var0: 0,
            to: address(this),
            validator: address(this),
            securityDepositValue: 0.01 ether,
            var1: 0,
            var2: 0,
            var3: 0,
            var4: 1,
            var5: 0,
            var6: 0,
            var7: 0
        });
        protocol.i_addPendingAction(address(this), pendingAction);
        (, uint128 previousRawIndex) = protocol.i_getPendingAction(address(this));
        protocol.i_clearPendingAction(address(this), previousRawIndex);

        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingAction(address(this));

        assertTrue(action.action == ProtocolAction.None, "action should be None");
        assertEq(rawIndex, 0, "rawIndex should be 0");
        assertTrue(protocol.queueEmpty(), "queue should be empty");
    }

    /**
     * @custom:scenario The `removeStalePendingAction` function return 0 when there is no pending action, the action
     * is different than ValidateOpenPosition or version calculated equal to tickVersion
     * @custom:given A protocol without any pending action
     * @custom:or a pending action different than `ValidateOpenPosition`
     * @custom:or a pending action with a tick version equal to the current tick version
     * @custom:when removeStalePendingAction is called
     * @custom:then The protocol should return 0
     */
    function test_removeStalePendingActionReturnZero() public {
        assertEq(protocol.i_removeStalePendingAction(address(this)), 0, "should return 0, no pending action");

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateWithdrawal,
            timestamp: uint40(block.timestamp - 1 days),
            var0: 0,
            to: address(this),
            validator: address(this),
            securityDepositValue: 0.01 ether,
            var1: 0,
            var2: 0,
            var3: 0,
            var4: 1,
            var5: 0,
            var6: 0,
            var7: 0
        });
        protocol.i_addPendingAction(address(this), pendingAction);
        assertEq(
            protocol.i_removeStalePendingAction(address(this)),
            0,
            "should return 0, action is different than ValidateOpenPosition"
        );

        LongPendingAction memory longPendingAction = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp - 1 days),
            closeLiqPenalty: 0,
            to: address(this),
            validator: USER_1,
            securityDepositValue: 0.01 ether,
            tick: 1,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: protocol.getTickVersion(1),
            index: 0,
            liqMultiplier: 0,
            closeBoundedPositionValue: 0
        });
        protocol.i_addPendingAction(USER_1, protocol.i_convertLongPendingAction(longPendingAction));
        assertEq(
            protocol.i_removeStalePendingAction(USER_1), 0, "should return 0, version calculated equal to tickVersion"
        );
    }

    /**
     * @custom:scenario The `removeStalePendingAction` function return the security deposit value
     * @custom:given A protocol with a pending action that is stale
     * @custom:when removeStalePendingAction is called
     * @custom:then The protocol should return the security deposit value
     */
    function test_removeStalePendingAction() public {
        protocol.setTickVersion(1, 5);
        LongPendingAction memory longPendingAction = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp - 1 days),
            closeLiqPenalty: 0,
            to: address(this),
            validator: USER_1,
            securityDepositValue: 0.01 ether,
            tick: 1,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: protocol.getTickVersion(1) - 1,
            index: 0,
            liqMultiplier: 0,
            closeBoundedPositionValue: 0
        });
        protocol.i_addPendingAction(USER_1, protocol.i_convertLongPendingAction(longPendingAction));
        vm.expectEmit();
        emit StalePendingActionRemoved(
            USER_1,
            PositionId({
                tick: longPendingAction.tick,
                tickVersion: longPendingAction.tickVersion,
                index: longPendingAction.index
            })
        );
        uint256 securityDeposit = protocol.i_removeStalePendingAction(USER_1);
        assertEq(securityDeposit, 0.01 ether, "should return the security deposit value");
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingAction(USER_1);
        assertTrue(action.action == ProtocolAction.None, "action should be None");
        assertEq(rawIndex, 0, "rawIndex should be 0");
    }

    /**
     * @custom:scenario The `calculateFee` function call with fundAsset greater than 0
     * @custom:when calculateFee is called with a fund and fundAsset greater than 0
     * @custom:then The function should return the expected fee, fundWithFee and fundAssetWithFee
     */
    function test_calculateFeeMoreThanZero() public {
        int256 fundAsset = 1000 ether;

        uint16 protocolFeeBps = protocol.getProtocolFeeBps();
        uint256 bpsDivisor = protocol.BPS_DIVISOR();
        uint256 expectedFee = (uint256(fundAsset) * protocolFeeBps) / bpsDivisor;

        (int256 fee, int256 fundAssetWithFee) = protocol.i_calculateFee(fundAsset);

        assertEq(uint256(fee), expectedFee, "fee should be equal to fundAsset * protocolFeeBps / bpsDivisor");
        assertEq(
            uint256(fundAssetWithFee),
            uint256(fundAsset) - expectedFee,
            "fundAssetWithFee should be equal to fundAsset - fee"
        );
    }

    /**
     * @custom:scenario The `calculateFee` function call with fundAsset equal to 0
     * @custom:when calculateFee is called with a fund greater than 0 and fundAsset equal to 0
     * @custom:then The function should return 0 for the fee and fundAssetWithFee
     * and fundWithFee should be equal to fund
     */
    function test_calculateFeeEqualZero() public {
        (int256 fee, int256 fundAssetWithFee) = protocol.i_calculateFee(0);

        assertEq(fee, 0, "fee should be 0");
        assertEq(fundAssetWithFee, 0, "fundAssetWithFee should be equal to fund");
    }

    /**
     * @custom:scenario The `calculateFee` function call with fundAsset less than 0
     * @custom:when calculateFee is called with a fund greater than 0 and fundAsset less than 0
     * @custom:then The function should return the expected fee, fundWithFee and fundAssetWithFee
     */
    function test_calculateFeeLessThanZero() public {
        int256 fundAsset = -1;

        uint16 protocolFeeBps = protocol.getProtocolFeeBps();
        uint256 bpsDivisor = protocol.BPS_DIVISOR();
        uint256 expectedFee = (uint256(-fundAsset) * protocolFeeBps) / bpsDivisor;

        (int256 fee, int256 fundAssetWithFee) = protocol.i_calculateFee(fundAsset);

        assertEq(uint256(fee), expectedFee, "fee should be equal to fundAsset * protocolFeeBps / bpsDivisor");
        assertEq(
            uint256(fundAssetWithFee),
            uint256(fundAsset) - expectedFee,
            "fundAssetWithFee should be equal to fundAsset - fee"
        );
    }
}
