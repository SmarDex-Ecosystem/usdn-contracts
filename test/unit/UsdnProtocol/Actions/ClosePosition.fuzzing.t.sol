// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests for the "close position" part of the protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 100_000 wstETH in their wallet
 */
contract TestUsdnProtocolActionsClosePositionFuzzing is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    struct TestData {
        uint256 protocolTotalExpo;
        uint256 initialPosCount;
        uint256 userBalanceBefore;
    }

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Initiate and validate a partial close of a position until the position is fully closed
     * @custom:given A user with 100_000 wsteth
     * @custom:when The owner of the position close the position partially n times
     * @custom:and and fully close the position if there is any leftover
     * @custom:then The state of the protocol is updated
     * @custom:and the user receives all of his funds back with less than 0.000000000000001% error
     * @param iterations The amount of time we want to close the position
     * @param amountToOpen The amount of assets in the position
     * @param amountToClose The amount to close per iteration
     */
    function testFuzz_closePositionWithAmount(uint256 iterations, uint256 amountToOpen, uint256 amountToClose) public {
        TestData memory data;
        // Bound values
        iterations = bound(iterations, 1, 10);
        amountToOpen = bound(amountToOpen, 1 ether, 100_000 ether);

        data.protocolTotalExpo = protocol.getTotalExpo();
        data.initialPosCount = protocol.getTotalLongPositions();
        data.userBalanceBefore = amountToOpen;

        assertEq(wstETH.balanceOf(address(this)), 0, "User should have no wstETH");

        bytes memory priceData = abi.encode(params.initialPrice);
        PositionId memory posId = setUpUserPositionInLong(
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
            (Position memory posBefore,) = protocol.getLongPosition(posId);
            amountToClose = bound(amountToClose, 1, posBefore.amount);
            amountClosed += amountToClose;

            protocol.initiateClosePosition(
                posId,
                uint128(amountToClose),
                DISABLEMINPRICE,
                address(this),
                payable(address(this)),
                priceData,
                EMPTY_PREVIOUS_DATA
            );
            _waitDelay();
            protocol.i_validateClosePosition(address(this), priceData);

            (Position memory posAfter,) = protocol.getLongPosition(posId);
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
                posId,
                uint128(amountToOpen - amountClosed),
                DISABLEMINPRICE,
                address(this),
                payable(address(this)),
                priceData,
                EMPTY_PREVIOUS_DATA
            );
            _waitDelay();
            protocol.i_validateClosePosition(address(this), priceData);
        }

        (Position memory pos,) = protocol.getLongPosition(posId);
        assertEq(pos.amount, 0, "Amount left should be 0");
        assertEq(pos.user, address(0), "Position should have been deleted from the tick array");

        assertEq(data.protocolTotalExpo, protocol.getTotalExpo(), "Total expo should be the same");
        assertEq(data.initialPosCount, protocol.getTotalLongPositions(), "Amount of positions should be the same");
        assertApproxEqRel(
            data.userBalanceBefore,
            wstETH.balanceOf(address(this)),
            1e1, // 0.000000000000001%
            "The user should have gotten back approximately all of his assets"
        );
    }
}
