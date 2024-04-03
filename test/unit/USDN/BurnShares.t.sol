// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `burnShares` function of `USDN`
 * @custom:background Given a user with 100e36 shares
 * @custom:and The contract has the `MINTER_ROLE` and `REBASER_ROLE`
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnBurnShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mintShares(USER_1, 100e36);
    }

    /**
     * @custom:scenario Burning shares from the zero address
     * @custom:when 50e36 shares are burned from the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidSender` error
     * @dev This function is not available in the USDN contract, only in the test handler
     */
    function test_RevertWhen_burnSharesFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        usdn.i_burnShares(address(0), 50e36, 50 ether);
    }
}
