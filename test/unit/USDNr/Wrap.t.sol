// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `wrap` function of `USDNr` contract
contract TestUsdnrWrap is UsdnrTokenFixture {
    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), 100 ether);
        usdn.approve(address(usdnr), type(uint256).max);
    }

    /**
     * @custom:scenario Wrap USDN to USDNr
     * @custom:when The wrap function is called with an amount of USDN
     * @custom:then The user balance of USDNr increases by the same amount
     * @custom:then The total supply of USDNr increases by the same amount
     * @custom:then The total wrapped USDN increases by the same amount
     */
    function test_usdnrWrap() public {
        uint256 amount = 10 ether;
        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 usdnContractBalance = usdn.balanceOf(address(usdnr));

        usdnr.wrap(amount);

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance + amount, "user USDNr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDNr supply");
        assertEq(usdn.balanceOf(address(usdnr)), usdnContractBalance + amount, "USDN balance in USDNr");
    }

    /**
     * @custom:scenario Revert when the wrap function is called with zero amount
     * @custom:when The wrap function is called with zero amount
     * @custom:then The transaction should revert with the error {USDNrZeroAmount}
     */
    function test_revertWhen_usdnrWrapZeroAmount() public {
        vm.expectRevert(IUsdnr.USDNrZeroAmount.selector);
        usdnr.wrap(0);
    }
}
