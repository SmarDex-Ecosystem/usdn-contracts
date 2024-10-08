// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/// @custom:feature Test the {_isActionable} internal function of the actions layer
contract TestUsdnProtocolActionsIsActionable is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check returned value of the `_isActionable` function when the timestamp is zero
     * @custom:given A call to the `_isActionable` function
     * @custom:when The timestamp is zero
     * @custom:then The function should return `false`
     */
    function test_returnFalseWhenTimestampZero() public view {
        bool actionable = protocol.i_isActionable(0, 1, 1, 1);
        assertFalse(actionable);
    }
}
