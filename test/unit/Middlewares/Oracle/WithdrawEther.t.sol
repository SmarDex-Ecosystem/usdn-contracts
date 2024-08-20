// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The `withdrawEther` function of the `OracleMiddleware` contract
 */
contract TestOracleMiddlewareWithdrawEther is OracleMiddlewareBaseFixture {
    function setUp() public override {
        super.setUp();
        vm.deal(address(oracleMiddleware), 1 ether);
    }

    /**
     * @custom:scenario A user that is not the owner calls withdrawEther
     * @custom:given A user that is not the owner
     * @custom:when withdrawEther is called
     * @custom:then the transaction reverts with an OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_withdrawEtherCalledByNonOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, USER_1, oracleMiddleware.ADMIN_ROLE()
            )
        );
        vm.prank(USER_1);
        oracleMiddleware.withdrawEther(USER_1);
    }

    /**
     * @custom:scenario A contract that cannot receive ether calls withdrawEther
     * @custom:given A contract that cannot receive ether as the owner of the middleware
     * @custom:when withdrawEther is called
     * @custom:then the transaction reverts with an OracleMiddlewareTransferFailed error
     */
    function test_RevertWhen_withdrawEtherToAnAddressThatCannotReceiveEther() public {
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareTransferFailed.selector, address(this)));
        oracleMiddleware.withdrawEther(address(this));
    }

    /**
     * @custom:scenario The owner calls the function with the zero address
     * @custom:given The caller being the owner
     * @custom:when withdrawEther is called with the to parameter being the zero address
     * @custom:then the transaction reverts with an OracleMiddlewareTransferToZeroAddress error
     */
    function test_RevertWhen_withdrawEtherToTheZeroAddress() public {
        vm.expectRevert(OracleMiddlewareTransferToZeroAddress.selector);
        oracleMiddleware.withdrawEther(address(0));
    }

    /**
     * @custom:scenario The owner withdraws the ether in the contract
     * @custom:given A user that is the owner
     * @custom:when withdrawEther is called
     * @custom:then the ether balance of the contract is sent to the caller
     */
    function test_withdrawEther() public {
        uint256 userBalanceBefore = USER_1.balance;
        uint256 middlewareBalanceBefore = address(oracleMiddleware).balance;

        oracleMiddleware.withdrawEther(USER_1);

        assertEq(address(oracleMiddleware).balance, 0, "No ether should be left in the middleware");
        assertEq(
            userBalanceBefore + middlewareBalanceBefore,
            USER_1.balance,
            "Middleware ether balance should have been transferred to the user"
        );
    }
}
