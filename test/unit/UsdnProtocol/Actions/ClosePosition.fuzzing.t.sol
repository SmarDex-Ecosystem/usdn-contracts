// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import {
    ProtocolAction,
    LongPendingAction,
    PendingAction,
    Position
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature The close position functions of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 100_000 wstETH in their wallet
 * @custom:and A position with 500 wstETH in collateral
 */
contract TestUsdnProtocolActionsClosePositionFuzzing is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);

        vm.prank(ADMIN);
        protocol.setFundingSF(0);
        protocol.setEMA(0);
    }

    function testFuzz_closePositionWithAmount(uint256 iterations, uint256 amountToOpen, uint256 amountToClose)
        external
    {
        vm.skip(true);
        // Bound values
        iterations = bound(iterations, 1, 10);
        amountToOpen = bound(amountToOpen, 0.1 ether, wstETH.balanceOf(address(this)));

        uint256 protocolTotalExpo = protocol.getTotalExpo();
        uint256 positionsAmount = protocol.getTotalLongPositions();
        uint256 userBalanceBefore = wstETH.balanceOf(address(this));

        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        (int24 tick, uint256 tickVersion, uint256 index) =
            protocol.initiateOpenPosition(uint96(amountToOpen), params.initialPrice - 200 ether, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");

        uint256 amountClosed;
        for (uint256 i = 0; i < iterations; ++i) {
            Position memory posBefore = protocol.getLongPosition(tick, tickVersion, index);
            amountToClose = bound(amountToClose, 100_000, posBefore.amount);
            amountClosed += amountToClose;

            protocol.initiateClosePosition(tick, tickVersion, index, uint128(amountToClose), priceData, "");
            skip(oracleMiddleware.getValidationDelay() + 1);
            protocol.validateClosePosition(priceData, "");

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
            protocol.validateClosePosition(priceData, "");
        }

        Position memory pos = protocol.getLongPosition(tick, tickVersion, index);
        assertEq(pos.amount, 0, "Amount left should be 0");
        assertEq(pos.user, address(0), "Position should have been deleted from the tick array");

        assertEq(protocolTotalExpo, protocol.getTotalExpo(), "Total expo should be the same");
        assertEq(positionsAmount, protocol.getTotalLongPositions(), "Amount of positions should be the same");
        assertApproxEqAbs(
            userBalanceBefore,
            wstETH.balanceOf(address(this)),
            1000,
            "The user should have gotten back his asset approximatively"
        );
    }
}
