// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `mint` function of `USDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnMint is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Minting tokens to the zero address
     * @custom:when 100 tokens are minted to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_mintToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.mint(address(0), 100 ether);
    }
}
