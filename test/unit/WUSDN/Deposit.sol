// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `deposit` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnDeposit is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Deposit usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 usdn is deposited to wusdn
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 70 usdn are deposited to wusdn
     * @custom:and The total assets of wusdn are 130
     * @custom:and The total supply of wusdn is 65
     */
    function test_deposit() public {
        usdn.approve(address(wusdn), type(uint256).max);

        wusdn.deposit(30 ether, USER_1);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        wusdn.deposit(70 ether, USER_1);

        assertEq(wusdn.totalAssets(), 130 ether, "total assets");
        assertEq(wusdn.totalSupply(), 65 ether, "total supply");
    }
}
