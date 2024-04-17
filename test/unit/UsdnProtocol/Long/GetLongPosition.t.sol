// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

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
        _setUp(DEFAULT_PARAMS);
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

        assertEq(
            position.timestamp + 2 * (oracleMiddleware.getValidationDelay() + 1),
            block.timestamp,
            "wrong position timestamp"
        );

        assertEq(position.user, USER_1, "wrong position user");
        assertEq(position.totalExpo, 19_466_359_632_272_617_650, "wrong position totalExpo");
        assertEq(position.amount, OPEN_AMOUNT, "wrong position amount");
        assertEq(liquidationPenalty, 2, "wrong liquidationPenalty");
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

        protocol.liquidate(abi.encode(params.initialPrice / 3), 10);

        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolOutdatedTick.selector, tickVersion + 1, tickVersion)
        );
        protocol.getLongPosition(tick, tickVersion, index);
    }
}
