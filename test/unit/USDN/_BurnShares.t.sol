// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `_burnShares` function of `USDN`
 */
contract TestUsdnBurnShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
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
