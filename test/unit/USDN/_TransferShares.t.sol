// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `_transferShares` function of `USDN`
 */
contract TestUsdnTransferShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Transfer shares from zero address
     * @custom:when We try to transfer shares from the zero address
     * @custom:then The transaction reverts with the ERC20InvalidSender error
     */
    function test_RevertWhen_transferSharesFromZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        usdn.i_transferShares(address(0), address(this), 1e36, 1e18);
    }

    /**
     * @custom:scenario Transfer shares to zero address
     * @custom:when We try to transfer shares to the zero address
     * @custom:then The transaction reverts with the ERC20InvalidReceiver error
     */
    function test_RevertWhen_transferSharesToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.i_transferShares(address(this), address(0), 1e36, 1e18);
    }
}
