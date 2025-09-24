// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `unwrap` function of the `USDnr` contract
contract TestUsdnrUnwrap is UsdnrTokenFixture {
    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), 100 ether);
        usdn.approve(address(usdnr), type(uint256).max);
        usdnr.wrap(100 ether, address(this));
    }

    /**
     * @custom:scenario Unwrap USDnr to USDN
     * @custom:when The unwrap function is called with an amount of USDnr
     * @custom:then The user balance of USDnr decreases by the same amount
     * @custom:and The total supply of USDnr decreases by the same amount
     * @custom:and The total wrapped USDN decreases by the same amount
     */
    function test_unwrap() public {
        uint256 amount = 10 ether;
        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 usdnContractBalance = usdn.balanceOf(address(usdnr));

        usdnr.unwrap(amount, address(this));

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance - amount, "user USDnr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply - amount, "total USDnr supply");
        assertEq(usdn.balanceOf(address(usdnr)), usdnContractBalance - amount, "USDN balance in USDnr");
    }

    /**
     * @custom:scenario Unwrap USDnr to another address
     * @custom:when The unwrap function is called with a recipient address
     * @custom:then The user balance of USDnr decreases by the amount
     * @custom:and The total supply of USDnr decreases by the amount
     * @custom:and The recipient balance of USDN increases by the amount
     * @custom:and The total wrapped USDN decreases by the amount
     */
    function test_unwrapToAnotherAddress() public {
        uint256 amount = 10 ether;
        address recipient = address(1);

        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));

        uint256 initialUsdnContractBalance = usdn.balanceOf(address(usdnr));
        uint256 initialUsdnRecipientUsdnBalance = usdn.balanceOf(recipient);

        usdnr.unwrap(amount, recipient);

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance - amount, "user USDnr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply - amount, "total USDnr supply");

        assertEq(usdn.balanceOf(recipient), initialUsdnRecipientUsdnBalance + amount, "recipient USDN balance");
        assertEq(usdn.balanceOf(address(usdnr)), initialUsdnContractBalance - amount, "USDN balance in USDnr");
    }

    /**
     * @custom:scenario Revert when the unwrap function is called with zero amount
     * @custom:when The unwrap function is called with zero amount
     * @custom:then The transaction should revert with the error {USDnrZeroAmount}
     */
    function test_revertWhen_unwrapZeroAmount() public {
        vm.expectRevert(IUsdnr.USDnrZeroAmount.selector);
        usdnr.unwrap(0, address(this));
    }

    /**
     * @custom:scenario Revert when the unwrap function is called with zero recipient
     * @custom:when The unwrap function is called with zero recipient
     * @custom:then The transaction should revert with the error {USDnrZeroRecipient}
     */
    function test_revertWhen_unwrapZeroRecipient() public {
        vm.expectRevert(IUsdnr.USDnrZeroRecipient.selector);
        usdnr.unwrap(1, address(0));
    }
}
