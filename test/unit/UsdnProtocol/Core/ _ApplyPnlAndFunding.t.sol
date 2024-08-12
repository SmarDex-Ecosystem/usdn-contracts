// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

contract TestUsdnProtocolCoreApplyPnlAndFunding is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        super._setUp(params);
    }

    /**
     * @custom:given A USDN protocol initialized with an `initialPrice` at 2000$
     * @custom:when The _applyPnlAndFunding function is called with the same price
     * @custom:then The state values `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding` are updated
     */
    function test_applyPnlAndFunding() external {
        protocol.i_applyPnlAndFunding(DEFAULT_PARAMS.initialPrice, uint128(block.timestamp));
        assertEq(
            protocol.getLastPrice(),
            DEFAULT_PARAMS.initialPrice,
            "_lastPrice should be equal to i_applyPnlAndFunding new price"
        );
        assertEq(protocol.getLastUpdateTimestamp(), block.timestamp);
    }
}
