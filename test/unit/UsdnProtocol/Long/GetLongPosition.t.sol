// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The `getLongPosition` function of the USDN Protocol
 * @custom:background Given a balanced protocol
 */
contract TestGetLongPosition is UsdnProtocolBaseFixture {
    uint128 constant OPEN_AMOUNT = 10 ether;

    function setUp() external {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableFunding = false;
        _setUp(params);
    }

    /**
     * @custom:scenario Check the return value of the function `getLongPosition`
     * @custom:given A initialized protocol
     * @custom:and A user position is opened
     * @custom:when The function is called with user position arguments
     * @custom:then The function should return expected user position values
     */
    function test_getLongPosition() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, OPEN_AMOUNT, params.initialPrice / 2, params.initialPrice
        );

        (Position memory position, uint8 liquidationPenalty) = protocol.getLongPosition(tick, tickVersion, index);

        uint128 adjustedPrice =
            uint128(params.initialPrice + (params.initialPrice * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR());
        int24 effectiveTick = protocol.getEffectiveTickForPrice(params.initialPrice / 2);
        uint8 effectiveLiquidationPenalty = protocol.getTickLiquidationPenalty(effectiveTick);

        uint128 liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            effectiveTick - int24(uint24(effectiveLiquidationPenalty)) * protocol.getTickSpacing()
        );

        uint128 positionTotalExpo =
            uint128(FixedPointMathLib.fullMulDiv(OPEN_AMOUNT, adjustedPrice, adjustedPrice - liqPriceWithoutPenalty));

        assertEq(
            position.timestamp + 2 * (oracleMiddleware.getValidationDelay() + 1),
            block.timestamp,
            "wrong position timestamp"
        );

        assertEq(position.user, USER_1, "wrong position user");
        assertEq(position.totalExpo, positionTotalExpo, "wrong position totalExpo");
        assertEq(position.amount, OPEN_AMOUNT, "wrong position amount");
        assertEq(liquidationPenalty, effectiveLiquidationPenalty, "wrong liquidationPenalty");
    }

    /**
     * @custom:scenario Check the function `getLongPosition` revert in case tick version is outdated
     * @custom:given A initialized protocol
     * @custom:and A user position is opened with a initial tick version
     * @custom:and The wsteth price drop below the position liquidation price
     * @custom:and The position is liquidated
     * @custom:and The tick version of the position tick is incremented
     * @custom:when The function is called with user position arguments
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_getLongPositionOutdatedTick() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, OPEN_AMOUNT, params.initialPrice / 2, params.initialPrice
        );

        // we need to skip 1 minute to make the new price data fresh
        skip(1 minutes);
        protocol.liquidate(abi.encode(params.initialPrice / 3), 10);

        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolOutdatedTick.selector, tickVersion + 1, tickVersion)
        );
        protocol.getLongPosition(tick, tickVersion, index);
    }
}
