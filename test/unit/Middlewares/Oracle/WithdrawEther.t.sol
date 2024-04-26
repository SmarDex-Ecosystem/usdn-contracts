// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OracleMiddlewareBaseFixture } from "test/unit/Middlewares/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

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
     * @custom:then the transaction reverts with a OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_withdrawEtherCalledByNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        vm.prank(USER_1);
        oracleMiddleware.withdrawEther(USER_1);
    }

    /**
     * @custom:scenario A contract that cannot receive ether calls withdrawEther
     * @custom:given A contract that cannot receive ether as the owner of the middleware
     * @custom:when withdrawEther is called
     * @custom:then the transaction reverts with a OracleMiddlewareTransferFailed error
     */
    function test_RevertWhen_withdrawEtherToAnAddressThatCannotReceiveEther() public {
        vm.expectRevert(abi.encodeWithSelector(OracleMiddlewareTransferFailed.selector, address(this)));
        oracleMiddleware.withdrawEther(address(this));
    }

    /**
     * @custom:scenario The owner calls the function with the zero address
     * @custom:given The caller being the owner
     * @custom:when withdrawEther is called with the to parameter being the zero address
     * @custom:then the transaction reverts with a OracleMiddlewareTransferToZeroAddress error
     */
    function test_RevertWhen_withdrawEtherToTheZeroAddress() public {
        vm.expectRevert(OracleMiddlewareTransferToZeroAddress.selector);
        oracleMiddleware.withdrawEther(address(0));
    }

    /**
     * @custom:scenario The owner withdraw the ether in the contract
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
