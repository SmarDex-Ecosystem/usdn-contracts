// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

/**
 * @custom:feature The `mintShares` function of `USDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestUsdnMintShares is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Minting shares to the zero address
     * @custom:when 100 shares are minted to the zero address
     * @custom:then The transaction reverts with the `ERC20InvalidReceiver` error
     */
    function test_RevertWhen_mintSharesToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        usdn.mintShares(address(0), 100);
    }

    /**
     * @custom:scenario Minting shares that would overflow the total supply of shares
     * @custom:given The max amount of tokens has already been minted
     * @custom:when max amount of additional tokens are minted
     * @custom:then The transaction reverts with an overflow error
     */
    function test_RevertWhen_mintSharesOverflowTotal() public {
        usdn.mintShares(address(this), type(uint256).max);
        vm.expectRevert();
        usdn.mintShares(address(this), 1);
    }
}
