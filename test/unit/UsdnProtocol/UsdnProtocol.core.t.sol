// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check return values of the `funding` function
     * @custom:when The timestamp is the same as the initial timestamp
     * @custom:then The funding should be 0
     */
    function test_funding() public {
        (int256 fund, int256 longExpo, int256 vaultExpo) =
            protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp));
        assertEq(fund, 0, "funding should be 0 if no time has passed");
        assertEq(longExpo, 4.919970269703462172 ether, "longExpo if no time has passed");
        assertEq(vaultExpo, 10 ether, "vaultExpo if no time has passed");
    }

    /**
     * @custom:scenario Calling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp) - 1);
    }

    /**
     * @custom:scenario The sum of all long position's value is equal to the long side available balance
     * @custom:given No time has elapsed since the initialization
     * @custom:and The price of the asset is equal to the initial price
     * @custom:when The sum of all position values is calculated
     * @custom:then The long side available balance is equal to the sum of all position values
     * @dev Due to imprecision in the calculations, there are in practice a few wei of difference, but always in favor
     * of the protocol (see fuzzing tests)
     */
    function test_longAssetAvailable() public {
        // calculate the value of the init position
        uint128 initLiqPrice = protocol.getEffectivePriceForTick(protocol.minTick());
        uint256 initPosValue = protocol.positionValue(
            DEFAULT_PARAMS.initialPrice, initLiqPrice, protocol.FIRST_LONG_AMOUNT(), defaultPosLeverage
        );

        // calculate the value of the deployer's long position
        uint128 longLiqPrice =
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 2));
        uint256 longPosValue = protocol.positionValue(
            DEFAULT_PARAMS.initialPrice,
            longLiqPrice,
            DEFAULT_PARAMS.initialLong - protocol.FIRST_LONG_AMOUNT(),
            initialLongLeverage
        );

        // calculate the sum to know the theoretical long balance
        uint256 sumOfPositions = longPosValue + initPosValue;

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(uint256(protocol.longAssetAvailable(DEFAULT_PARAMS.initialPrice)), sumOfPositions, "long balance");
    }

    /**
     * @dev Helper function to initiate a new position and liquidate it before it gets validated
     * @return tick_ The tick of the new position
     * @return tickVersion_ The tick version of the new position
     * @return index_ The index of the new position
     */
    function _createStalePendingActionHelper() internal returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        wstETH.mintAndApprove(address(this), 2 ether, address(protocol), type(uint256).max);
        // create a pending action with a liquidation price around $1700
        bytes memory priceData = abi.encode(uint128(2000 ether));
        (tick_, tickVersion_, index_) = protocol.initiateOpenPosition(1 ether, 1700 ether, priceData, "");

        // the price drops to $1500 and the position gets liquidated
        skip(30);
        priceData = abi.encode(uint128(1500 ether));
        protocol.liquidate(priceData, 10);

        // the pending action is stale
        (, uint256 currentTickVersion) = protocol.tickHash(tick_);
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.var3, tickVersion_, "tick version");
        assertTrue(action.var3 != currentTickVersion, "current tick version");
    }

    /**
     * @custom:scenario A pending new long position gets liquidated
     * @custom:given A pending new position was liquidated before being validated
     * @custom:and The pending action is stale (tick version mismatch)
     * @custom:when The user opens another position
     * @custom:then The protocol emits a `StalePendingActionRemoved` event
     * @custom:and The transaction does not revert
     */
    function test_stalePendingActionReInit() public {
        (int24 tick, uint256 tickVersion, uint256 index) = _createStalePendingActionHelper();

        bytes memory priceData = abi.encode(uint128(1500 ether));
        // we should be able to open a new position
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.initiateOpenPosition(1 ether, 1000 ether, priceData, "");
    }

    /**
     * @custom:scenario A pending new long position gets liquidated and then validated
     * @custom:given A pending new position was liquidated before being validated
     * @custom:and The pending action is stale (tick version mismatch)
     * @custom:when The user tries to validate the pending action
     * @custom:then The protocol emits a `StalePendingActionRemoved` event
     * @custom:and The transaction does not revert
     */
    function test_stalePendingActionValidate() public {
        (int24 tick, uint256 tickVersion, uint256 index) = _createStalePendingActionHelper();

        bytes memory priceData = abi.encode(uint128(1500 ether));
        // validating the action emits the proper event
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.validateOpenPosition(priceData, "");
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when long and vault expos are equal
     * @custom:then fund should be equal to EMA
     */
    function test_fundingWhenEqualExpo() public {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(20 ether, price / 2, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        // we create a deposit to make the long and vault expos equal
        protocol.initiateDeposit(
            uint128(uint256(protocol.i_longTradingExpo(price) - protocol.i_vaultTradingExpo(price))), priceData, ""
        );
        protocol.validateDeposit(priceData, "");

        assertEq(
            protocol.i_longTradingExpo(price),
            protocol.i_vaultTradingExpo(price),
            "long and vault expos should be equal"
        );
        (int256 fund_,,) = protocol.funding(price, uint128(DEFAULT_PARAMS.initialTimestamp + 60));
        assertEq(fund_, protocol.EMA(), "funding should be equal to EMA");
    }

    /**
     * TO DO : natspec
     */
    function test_funding_NegLong_ZeroVault() public {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(1000 ether, price * 90 / 100, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        skip(25);
        protocol.liquidate(abi.encode(price / 100), 10);
        int256 EMA = protocol.EMA();
        uint256 fundingSF = protocol.fundingSF();
        (int256 fund_,,) = protocol.funding(price / 100, uint128(block.timestamp));
        emit log_named_int("fund_", fund_);
        emit log_named_int("mul", -int256(fundingSF) + EMA);
    }
}
