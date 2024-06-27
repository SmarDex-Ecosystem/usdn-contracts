// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { UsdnProtocolHandler } from "../utils/Handler.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

contract TestUsdnProtocolCoreFunding is UsdnProtocolBaseFixture {
    UsdnProtocolHandler.FundingStorage s;
    int256 constant EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4));

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);
        s = UsdnProtocolHandler.FundingStorage({
            totalExpo: protocol.getTotalExpo(),
            balanceLong: protocol.getBalanceLong(),
            balanceVault: protocol.getBalanceVault(),
            lastUpdateTimestamp: uint128(block.timestamp),
            fundingSF: protocol.getFundingSF()
        });
    }

    function test_fundingNoTimeElapsed() public {
        (int256 fund, int256 longExpo) = protocol.i_funding(s, s.lastUpdateTimestamp, EMA);
        assertEq(fund, 0, "funding should be 0 if no time has passed");
        assertEq(longExpo, int256(s.totalExpo - s.balanceLong), "longExpo if no time has passed");
    }
}
