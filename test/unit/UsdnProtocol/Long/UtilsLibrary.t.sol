// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constant } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Test the {UsdnProtocolUtilsLibrary} of the usdn protocol
 * @custom:background An initialized usdn protocol contract with 200 ether in the vault
 * @custom:and 100 ether in the long side
 */
contract TestUsdnProtocolUtilsLibrary is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Test the {_calcFixedPrecisionMultiplier} function
     * @custom:when The function is called with an accumulator value equal 0
     * @custom:then The function should return the liquidation multiplier equal to 1.0
     */
    function test_calcFixedPrecisionMultiplierReturnOne() public view {
        uint256 multiplier = 10 ** Constant.LIQUIDATION_MULTIPLIER_DECIMALS;
        HugeUint.Uint512 memory accumulator = HugeUint.Uint512(0, 0);
        uint256 result = protocol.i_calcFixedPrecisionMultiplier(10, 10, accumulator);
        assertEq(result, multiplier, "multiplier should be 1.0");
    }
}
