// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests for the "close position" part of the protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 100_000 wstETH in their wallet
 */
contract TestUsdnProtocolActionsClosePositionFuzzing is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Initiate and validate a partial close of a position until the position is fully closed
     * @custom:given A user with 100_000 wsteth
     * @custom:when The owner of the position close the position partially n times
     * @custom:and and fully close the position if there is any leftover
     * @custom:then The state of the protocol is updated
     * @custom:and the user receives all of his funds back
     *
     * @param iterations The amount of time we want to close the position
     * @param amountToOpen The amount of assets in the position
     * @param amountToClose The amount to close per iteration
     */
    function testFuzz_closePositionWithAmount(uint256 iterations, uint256 amountToOpen, uint256 amountToClose)
        external
    {
        // Bound values
        iterations = bound(iterations, 1, 10);
        amountToOpen = bound(amountToOpen, 1, 100_000 ether);

        uint256 protocolTotalExpo = protocol.getTotalExpo();
        uint256 initialPosCount = protocol.getTotalLongPositions();
        uint256 userBalanceBefore = amountToOpen;

        bytes memory priceData = abi.encode(params.initialPrice);
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: uint128(amountToOpen),
                desiredLiqPrice: params.initialPrice - (params.initialPrice / 5),
                price: params.initialPrice
            })
        );

        uint256 amountClosed;
        for (uint256 i = 0; i < iterations; ++i) {
            (Position memory posBefore,) = protocol.getLongPosition(tick, tickVersion, index);
            amountToClose = bound(amountToClose, 1, posBefore.amount);
            amountClosed += amountToClose;

            protocol.initiateClosePosition(
                tick, tickVersion, index, uint128(amountToClose), priceData, EMPTY_PREVIOUS_DATA, address(this)
            );
            _waitDelay();
            protocol.i_validateClosePosition(address(this), address(this), priceData);

            (Position memory posAfter,) = protocol.getLongPosition(tick, tickVersion, index);
            assertEq(
                posAfter.amount,
                posBefore.amount - amountToClose,
                "Amount to close should have been subtracted from position amount"
            );

            if (posAfter.amount == 0) {
                break;
            }
        }

        // Close the what's left of the position
        if (amountClosed != amountToOpen) {
            protocol.initiateClosePosition(
                tick,
                tickVersion,
                index,
                uint128(amountToOpen - amountClosed),
                priceData,
                EMPTY_PREVIOUS_DATA,
                address(this)
            );
            _waitDelay();
            protocol.i_validateClosePosition(address(this), address(this), priceData);
        }

        (Position memory pos,) = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(pos.amount, 0, "Amount left should be 0");
        assertEq(pos.user, address(0), "Position should have been deleted from the tick array");

        assertEq(protocolTotalExpo, protocol.getTotalExpo(), "Total expo should be the same");
        assertEq(initialPosCount, protocol.getTotalLongPositions(), "Amount of positions should be the same");
        assertApproxEqAbs(
            userBalanceBefore,
            wstETH.balanceOf(address(this)),
            iterations + 1,
            "The user should have gotten back approximately all of his assets"
        );
    }
}
