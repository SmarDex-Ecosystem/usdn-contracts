// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "../../../../utils/Constants.sol";
import { OracleMiddlewareWithRedstoneFixture } from "../../utils/Fixtures.sol";

/**
 * @custom:feature The `setPenaltyBps` function of the `OracleMiddleware` contract
 */
contract TestOracleMiddlewareSetPenaltyBps is OracleMiddlewareWithRedstoneFixture {
    /**
     * @custom:scenario A user that without the right role calls setPenaltyBps
     * @custom:given A user without the right role
     * @custom:when setPenaltyBps is called
     * @custom:then the transaction reverts with an AccessControlUnauthorizedAccount error
     */
    function test_RevertWhen_setPenaltyBpsWithoutTheRightRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER_1, oracleMiddleware.ADMIN_ROLE()
            )
        );
        vm.prank(USER_1);
        oracleMiddleware.setPenaltyBps(20);
    }

    /**
     * @custom:scenario Revert when the owner set a new penaltyBps value that is greater than 1000
     * @custom:given The caller being the owner
     * @custom:when setPenaltyBps is called
     * @custom:then the transaction reverts with an OracleMiddlewareInvalidPenaltyBps error
     */
    function test_RevertWhen_setPenaltyBpsGreaterThanOneHundred() public {
        vm.expectRevert(OracleMiddlewareInvalidPenaltyBps.selector);
        oracleMiddleware.setPenaltyBps(1001);
    }

    /**
     * @custom:scenario The owner set a new penaltyBps value
     * @custom:given A user that is the owner
     * @custom:when setPenaltyBps is called
     * @custom:then the _penaltyBps value is updated
     */
    function test_setPenaltyBps() public {
        vm.expectEmit();
        emit PenaltyBpsUpdated(1000);
        oracleMiddleware.setPenaltyBps(1000);

        assertEq(oracleMiddleware.getPenaltyBps(), 1000, "Invalid penaltyBps value");
    }
}
