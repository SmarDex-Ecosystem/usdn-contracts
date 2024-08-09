// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature The `getLongPosition` function of the USDN Protocol
 * @custom:background Given a balanced protocol
 */
contract TestGetLongPosition is UsdnProtocolBaseFixture {
    uint128 constant OPEN_AMOUNT = 10 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = false;
        params.flags.enableProtocolFees = false;
        params.flags.enablePositionFees = true;
        _setUp(params);
    }

    /**
     * @custom:scenario Check the return value of the function `getCurrentLongPosition`
     * @custom:given A initialized protocol
     * @custom:and A user position is validated
     * @custom:when The function is called with user position arguments
     * @custom:then The function should return expected user position values
     */
    function test_getCurrentLongPosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: OPEN_AMOUNT,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        (Position memory position,) = protocol.getLongPosition(posId);

        int24 expectedTick = protocol.getEffectiveTickForPrice(params.initialPrice / 2);
        // index = 0, because the position is the first in the list
        Position memory posRet = protocol.getCurrentLongPosition(expectedTick, 0);

        assertEq(position.validated, posRet.validated, "validated");
        assertEq(position.timestamp, posRet.timestamp, "timestamp");
        assertEq(position.user, posRet.user, "user");
        assertEq(position.totalExpo, posRet.totalExpo, "totalExpo");
        assertEq(position.amount, posRet.amount, "amount");
    }

    /**
     * @custom:scenario Check the return value of the function `getLongPosition`
     * @custom:given A initialized protocol
     * @custom:and A user position is opened
     * @custom:when The function is called with user position arguments before the validation
     * @custom:and The function is called with user position arguments after the validation
     * @custom:then The function should return expected user position values
     */
    function test_getLongPosition() public {
        int24 expectedTick = protocol.getEffectiveTickForPrice(params.initialPrice / 2);
        uint128 adjustedPrice =
            uint128(params.initialPrice + (params.initialPrice * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR());
        uint8 liqPenalty = protocol.getTickLiquidationPenalty(expectedTick);

        uint128 liqPriceWithoutPenalty =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(expectedTick, liqPenalty));
        uint128 totalExpo =
            uint128(FixedPointMathLib.fullMulDiv(OPEN_AMOUNT, adjustedPrice, adjustedPrice - liqPriceWithoutPenalty));

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: OPEN_AMOUNT,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        (Position memory position, uint8 liquidationPenalty) = protocol.getLongPosition(posId);

        uint256 expectedTimestamp = block.timestamp - oracleMiddleware.getValidationDelay() - 1;
        assertEq(position.timestamp, expectedTimestamp, "initiate position timestamp");
        assertEq(position.user, USER_1, "initiate position user");
        assertEq(position.totalExpo, totalExpo, "initiate position totalExpo");
        assertEq(position.amount, OPEN_AMOUNT, "initiate position amount");
        assertEq(liquidationPenalty, liqPenalty, "initiate liquidationPenalty");

        liqPriceWithoutPenalty =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(expectedTick, liqPenalty));
        totalExpo =
            uint128(FixedPointMathLib.fullMulDiv(OPEN_AMOUNT, adjustedPrice, adjustedPrice - liqPriceWithoutPenalty));

        vm.prank(USER_1);
        protocol.validateOpenPosition(USER_1, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);

        (position, liquidationPenalty) = protocol.getLongPosition(posId);

        assertEq(position.timestamp, expectedTimestamp, "validate position timestamp");
        assertEq(position.user, USER_1, "validate position user");
        assertEq(position.totalExpo, totalExpo, "validate position totalExpo");
        assertEq(position.amount, OPEN_AMOUNT, "validate position amount");
        assertEq(liquidationPenalty, liqPenalty, "validate liquidationPenalty");
    }

    /**
     * @custom:scenario Check the function `getLongPosition` revert in case tick version is outdated
     * @custom:given A initialized protocol
     * @custom:and A user position is opened with a initial tick version
     * @custom:and The wsteth price drops below the position liquidation price
     * @custom:and The position is liquidated
     * @custom:and The tick version of the position tick is incremented
     * @custom:when The function is called with user position arguments
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_getLongPositionOutdatedTick() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: OPEN_AMOUNT,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        _waitBeforeLiquidation();
        protocol.mockLiquidate(abi.encode(params.initialPrice / 3), 10);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolOutdatedTick.selector, posId.tickVersion + 1, posId.tickVersion
            )
        );
        protocol.getLongPosition(posId);
    }
}
