// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction, PendingAction, Position, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
     */
    function test_funding() public {
        int256 longExpo = int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong());
        (int256 fund, int256 oldLongExpo) = protocol.funding(uint128(params.initialTimestamp));
        assertEq(fund, 0, "funding should be 0 if no time has passed");
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
    function test_longAssetAvailable() public {
        // calculate the value of the deployer's long position
        uint128 longLiqPrice =
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(params.initialPrice / 2));

        (Position memory firstPos,) = protocol.getLongPosition(
            PositionId(
                protocol.getEffectiveTickForPrice(longLiqPrice)
                    + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing(),
                0,
                0
            )
        );

        int256 longPosValue = protocol.i_positionValue(params.initialPrice, longLiqPrice, firstPos.totalExpo);

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(protocol.i_longAssetAvailable(params.initialPrice), longPosValue, "long balance");
    }

    /**
     * @custom:scenario EMA updated correctly
     * @custom:given a negative funding
     * @custom:and an action for a smaller period than the EMA period
     * @custom:then EMA should be greater than the last funding
     */
    function test_updateEma_negFunding() public {
        // we create a deposit and skip 1 day and call liquidate() to have a negative funding
        bytes memory priceData = abi.encode(params.initialPrice);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 10 ether, params.initialPrice);
        skip(1 days);
        protocol.testLiquidate(priceData, 1);

        int256 lastFunding = protocol.getLastFunding();
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.testLiquidate(priceData, 1);

        assertGt(protocol.getEMA(), lastFunding);
    }

    /**
     * @custom:scenario EMA updated correctly
     * @custom:given a positive funding
     * @custom:and an action for a smaller period than the EMA period
     * @custom:then EMA should be lower than the last funding
     */
    function test_updateEma_posFunding() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 200 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        int256 lastFunding = protocol.getLastFunding();
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.testLiquidate(abi.encode(params.initialPrice), 1);

        assertLt(protocol.getEMA(), lastFunding);
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when long and vault expos are equal
     * @custom:then fund should be equal to EMA
     */
    function test_fundingWhenEqualExpo() public {
        assertEq(
            protocol.i_longTradingExpo(params.initialPrice),
            protocol.i_vaultTradingExpo(params.initialPrice),
            "long and vault expos should be equal"
        );

        int256 EMA = protocol.getEMA();
        (int256 fund_, int256 oldLongExpo) = protocol.funding(uint128(params.initialTimestamp + 60));
        assertEq(fund_, EMA, "funding should be equal to EMA");
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
        protocol.testLiquidate(priceData, 1);

        int256 lastFunding = protocol.getLastFunding();
        skip(protocol.getEMAPeriod() + 1);
        // we call liquidate() to update the EMA
        protocol.testLiquidate(priceData, 1);

        assertEq(protocol.getEMA(), lastFunding, "EMA should be equal to last funding");
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
        protocol.testLiquidate(abi.encode(price / 100), 10);
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (int256 fund_,) = protocol.funding(uint128(block.timestamp));

        assertEq(
            fund_,
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
        protocol.testLiquidate(abi.encode(price * 100), 10);
        assertGt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be positive");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (int256 fund_,) = protocol.funding(uint128(block.timestamp));

        assertEq(
            fund_,
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

        (int256 fund,) = protocol.funding(uint128(block.timestamp));
        assertGt(fund, 0, "funding should be positive");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        int256 available = protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.testLiquidate(priceData, 5);
        assertEq(available, int256(protocol.getBalanceLong()), "long balance != available");
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

        (int256 fund,) = protocol.funding(uint128(block.timestamp));
        assertLt(fund, 0, "funding should be negative");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        int256 available = protocol.longAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.testLiquidate(abi.encode(price), 5);

        assertEq(available, int256(protocol.getBalanceLong()), "long balance != available");
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

        (int256 fund,) = protocol.funding(uint128(block.timestamp));
        assertLt(fund, 0, "funding should be negative");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        int256 available = protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.testLiquidate(abi.encode(price), 5);

        assertEq(available, int256(protocol.getBalanceVault()), "vault balance != available");
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

        (int256 fund,) = protocol.funding(uint128(block.timestamp));
        assertGt(fund, 0, "funding should be positive");

        // we have to subtract 30 seconds from the timestamp because of the mock oracle middleware behavior
        int256 available = protocol.vaultAssetAvailableWithFunding(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.testLiquidate(priceData, 5);
        assertEq(available, int256(protocol.getBalanceVault()), "vault balance != available");
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
    function test_emptyPendingAction() public {
        (PendingAction memory action, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.None, "action should be None");
        assertEq(action.user, address(0), "user should be empty");
        assertEq(action.to, address(0), "to should be empty");
        assertEq(rawIndex, 0, "rawIndex should be 0");
    }

    /**
     * @custom:scenario The `getPendingAction` function returns the action when there is one
     * @custom:given There is a pending action for this user
     * @custom:when There is a pending action
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
        assertEq(action.user, address(this), "user should be this contract");
        assertEq(action.to, address(this), "to should be this contract");
        assertEq(rawIndex, 1, "rawIndex should be 1");
    }
}
