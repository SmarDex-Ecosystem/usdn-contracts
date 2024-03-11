// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableFunding = false;
        params.enablePositionFees = false;
        params.enableProtocolFees = false;

        super._setUp(params);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);

        // Open a position to avoid a bug in _positionValue
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        protocol.initiateOpenPosition(
            uint128(wstETH.balanceOf(address(this)) / 2), params.initialPrice - 1000 ether, priceData, ""
        );
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");
    }

    function testFuzz_closePositionWithAmount(uint256 iterations, uint256 amountToOpen, uint256 amountToClose)
        external
    {
        // Bound values
        iterations = bound(iterations, 1, 10);
        // divided by 2 to have enough asset available to avoid bug in _positionValue
        amountToOpen = bound(amountToOpen, 1, wstETH.balanceOf(address(this)) / 2);

        uint256 protocolTotalExpo = protocol.getTotalExpo();
        uint256 positionsAmount = protocol.getTotalLongPositions();
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(uint128(amountToOpen), params.initialPrice - 200 ether, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");

        uint256 amountClosed;
        for (uint256 i = 0; i < iterations; ++i) {
            Position memory posBefore = protocol.getLongPosition(tick, tickVersion, index);
            amountToClose = bound(amountToClose, 1, posBefore.amount);
            amountClosed += amountToClose;

            protocol.initiateClosePosition(tick, tickVersion, index, uint128(amountToClose), priceData, "");
            skip(oracleMiddleware.getValidationDelay() + 1);
            protocol.i_validateClosePosition(address(this), priceData);

            Position memory posAfter = protocol.getLongPosition(tick, tickVersion, index);
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
                tick, tickVersion, index, uint128(amountToOpen - amountClosed), priceData, ""
            );
            skip(oracleMiddleware.getValidationDelay() + 1);
            protocol.i_validateClosePosition(address(this), priceData);
        }

        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(pos.amount, 0, "Amount left should be 0");
        assertEq(pos.user, address(0), "Position should have been deleted from the tick array");

        assertEq(protocolTotalExpo, protocol.getTotalExpo(), "Total expo should be the same");
        assertEq(positionsAmount, protocol.getTotalLongPositions(), "Amount of positions should be the same");
        assertApproxEqAbs(
            userBalanceBefore,
            wstETH.balanceOf(address(this)),
            iterations + 1,
            "The user should have gotten back his asset approximatively"
        );
    }
}
