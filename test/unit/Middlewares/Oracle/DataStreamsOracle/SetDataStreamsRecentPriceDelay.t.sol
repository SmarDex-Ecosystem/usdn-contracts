// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { OracleMiddlewareWithDataStreamsFixture } from "../../utils/Fixtures.sol";

/// @custom:feature The `setDataStreamsRecentPriceDelay` function of the `OracleMiddlewareWithDataStreams`.
contract TestOracleMiddlewareWithDataStreamsSetRecentPriceDelay is OracleMiddlewareWithDataStreamsFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Tests the `setDataStreamsRecentPriceDelay` function with a low delay.
     * @custom:when The function is called with a delay value considered too low.
     * @custom:then The call should revert with `OracleMiddlewareInvalidRecentPriceDelay`.
     */
    function test_RevertWhen_setRecentPriceDelayLowDelay() public {
        uint64 delay; // = 0
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareInvalidRecentPriceDelay.selector, delay));
        oracleMiddleware.setDataStreamsRecentPriceDelay(delay);
    }

    /**
     * @custom:scenario Tests the `setDataStreamsRecentPriceDelay` function with a high delay.
     * @custom:when The function is called with a delay value that exceeds the allowed limit.
     * @custom:then The call should revert with `OracleMiddlewareInvalidRecentPriceDelay`.
     */
    function test_RevertWhen_setRecentPriceDelayHighDelay() public {
        uint64 delay = type(uint64).max;
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareInvalidRecentPriceDelay.selector, delay));
        oracleMiddleware.setDataStreamsRecentPriceDelay(delay);
    }

    /**
     * @custom:scenario Tests the `setDataStreamsRecentPriceDelay` function with a valid delay.
     * @custom:when The function is called with a delay that meets all specified criteria.
     * @custom:then The transaction must be successful.
     * @custom:and The `_dataStreamsRecentPriceDelay` value must be updated to the new valid delay.
     */
    function test_setRecentPriceDelayValidDelay() public {
        uint64 delay = 1 minutes;

        vm.expectEmit();
        emit DataStreamsRecentPriceDelayUpdated(delay);
        oracleMiddleware.setDataStreamsRecentPriceDelay(delay);

        assertEq(
            oracleMiddleware.getDataStreamRecentPriceDelay(), delay, "Data stream recent price delay must be updated"
        );
    }
}
