// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `unwrap` function of `USDNr` contract
contract TestUsdnrUnwrap is UsdnrTokenFixture {
    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), 100 ether);
        usdn.approve(address(usdnr), type(uint256).max);
        usdnr.wrap(100 ether);
    }

    /**
     * @custom:scenario Unwrap USDNr to USDN
     * @custom:when The unwrap function is called with an amount of USDNr
     * @custom:then The user balance of USDNr decreases by the same amount
     * @custom:then The total supply of USDNr decreases by the same amount
     * @custom:then The total wrapped USDN decreases by the same amount
     */
    function test_usdnrUnwrap() public {
        uint256 amount = 10 ether;
        uint256 initialTotalWrapped = usdnr.getTotalWrapped();
        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 usdnContractBalance = usdn.balanceOf(address(usdnr));

        usdnr.unwrap(amount);

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance - amount, "user USDNr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply - amount, "total USDNr supply");
        assertEq(usdnr.getTotalWrapped(), initialTotalWrapped - amount, "total wrapped USDN");
        assertEq(usdn.balanceOf(address(usdnr)), usdnContractBalance - amount, "USDN balance in USDNr");
    }

    /**
     * @custom:scenario Call unwrap with zero amount
     * @custom:when The unwrap function is called with zero amount
     * @custom:then The transaction should revert with the error {USDNrZeroAmount}
     */
    function test_revertWhen_usdnrUnwrapZeroAmount() public {
        vm.expectRevert(IUsdnr.USDNrZeroAmount.selector);
        usdnr.unwrap(0);
    }
}
