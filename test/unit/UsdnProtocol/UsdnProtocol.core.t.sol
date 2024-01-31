// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

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
     * @custom:scenario A pending new long position gets liquidated
     * @custom:given A pending new position was liquidated before being validated
     * @custom:and The pending action is stale (tick version mismatch)
     * @custom:when The user opens another position
     * @custom:then The protocol emits a `StalePendingActionRemoved` event
     * @custom:and The transaction does not revert
     */
    function test_stalePendingActionReInit() public {
        wstETH.mint(address(this), 2 ether);
        wstETH.approve(address(protocol), type(uint256).max);

        // create a pending action with a liquidation price around $1700
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, 1700 ether, abi.encode(uint128(2000 ether)), "");

        // the price drops to $1500 and the position gets liquidated
        skip(30);
        protocol.liquidate(abi.encode(uint128(1500 ether)), 10);

        // the pending action is stale
        (, uint256 currentTickVersion) = protocol.tickHash(tick);
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.totalExpoOrTickVersion, tickVersion, "tick version");
        assertTrue(action.totalExpoOrTickVersion != currentTickVersion, "current tick version");

        // we should be able to open a new position
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.initiateOpenPosition(1 ether, 1000 ether, abi.encode(uint128(1500 ether)), "");
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
        wstETH.mint(address(this), 2 ether);
        wstETH.approve(address(protocol), type(uint256).max);

        // create a pending action with a liquidation price around $1700
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(1 ether, 1700 ether, abi.encode(uint128(2000 ether)), "");

        // the price drops to $1500 and the position gets liquidated
        skip(30);
        protocol.liquidate(abi.encode(uint128(1500 ether)), 10);

        // the pending action is stale
        (, uint256 currentTickVersion) = protocol.tickHash(tick);
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.totalExpoOrTickVersion, tickVersion, "tick version");
        assertTrue(action.totalExpoOrTickVersion != currentTickVersion, "current tick version");

        // validating the action emits the proper event
        vm.expectEmit();
        emit StalePendingActionRemoved(address(this), tick, tickVersion, index);
        protocol.validateOpenPosition(abi.encode(uint128(1500 ether)), "");
    }
}
