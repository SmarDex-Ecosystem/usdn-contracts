// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

import { IOracleMiddlewareEvents } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";

/**
 * @custom:feature The `getChainlinkTimeElapsedLimit` and `updateChainlinkTimeElapsedLimit` functions of
 * `OracleMiddleware`.
 */
contract TestOracleMiddlewareUpdateChainlinkTimeElapsedLimit is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Call the `getChainlinkTimeElapsedLimit` function.
     * @custom:when The value returned by the function is compared to the value used in the ChainlinkOracle constructor.
     * @custom:then It should succeed.
     */
    function test_chainlinkTimeElapsedLimit() public view {
        assertEq(oracleMiddleware.getChainlinkTimeElapsedLimit(), chainlinkTimeElapsedLimit);
    }

    /**
     * @custom:scenario Call the `updateChainlinkTimeElapsedLimit` function.
     * @custom:when We set a new value for the time elapsed limit.
     * @custom:then The `getChainlinkTimeElapsedLimit` should return the value set.
     */
    function test_updateChainlinkTimeElapsedLimit() public {
        uint256 newValue = chainlinkTimeElapsedLimit + 1 hours;

        vm.expectEmit();
        emit IOracleMiddlewareEvents.TimeElapsedLimitUpdated(newValue);
        oracleMiddleware.setChainlinkTimeElapsedLimit(newValue);

        assertEq(oracleMiddleware.getChainlinkTimeElapsedLimit(), newValue);
    }

    /**
     * @custom:scenario Call the `updateChainlinkTimeElapsedLimit` function with an address that is not the owner.
     * @custom:when An address that is not the owner calls the updateChainlinkTimeElapsedLimit function.
     * @custom:then It reverts with a OwnableUnauthorizedAccount error from Ownable
     */
    function test_RevertWhen_NonOwnerCallsUpdateChainlinkTimeElapsedLimit() public {
        uint256 newValue = chainlinkTimeElapsedLimit + 1 hours;

        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        oracleMiddleware.setChainlinkTimeElapsedLimit(newValue);
    }
}
