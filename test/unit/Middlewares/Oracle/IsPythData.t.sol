// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

/// @custom:feature The `_isPythData` function of `OracleMiddleware`
contract TestOracleMiddlewareIsPythData is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Check if data is pyth when data length is less than or equal to 32 bytes
     * @custom:when The data has a length lower than or equal to 32 bytes
     * @custom:then The function should return false
     */
    function test_isPythDataShortBytes() public view {
        assertFalse(oracleMiddleware.i_isPythData(""), "empty bytes");
        assertFalse(oracleMiddleware.i_isPythData(new bytes(32)), "32 bytes");
    }

    /**
     * @custom:scenario Check if data is pyth when data start with the magic bytes
     * @custom:given The data length is strictly more than 32 bytes
     * @custom:when The data starts with the magic bytes
     * @custom:then The function should return true
     */
    function test_isPythDataMagic() public view {
        assertTrue(oracleMiddleware.i_isPythData(MOCK_PYTH_DATA), "magic data");
    }

    /**
     * @custom:scenario Check if data is pyth when data length is more than 32 bytes
     * @custom:given The data doesn't start with the magic bytes
     * @custom:when The data has a higher length than 32 bytes
     * @custom:then The function should return false
     */
    function test_isPythDataLongBytes() public view {
        assertFalse(oracleMiddleware.i_isPythData(new bytes(33)), "33 bytes");
        assertFalse(oracleMiddleware.i_isPythData(new bytes(64)), "64 bytes");
    }
}
