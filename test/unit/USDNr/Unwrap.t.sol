// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

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
     * @custom:scenario Last unwrap after wrap with USDN rounding up
     * @custom:when The last user withdraws its USDN
     * @custom:and Multiple wrap have been made where the USDN amount was rounded up
     * @custom:then The transaction should reverts
     * @custom:when The USDNR reserve has been reached
     * @custom:then The transaction should succeed
     */
    function test_lastUnwrap() public {
        address user = address(this);
        assertEq(usdnr.totalSupply(), usdnr.balanceOf(user), "the user should be the only one");

        // we mint divisor/2 shares, so the USDN amount is rounded up
        // resulting in 2 weis of USDnr minted for 1 wei of USDN deposited
        usdn.mintShares(user, usdn.divisor() / 2);
        usdnr.wrap(1, user);
        usdn.mintShares(user, usdn.divisor() / 2);
        usdnr.wrap(1, user);

        uint256 usdnrBalanceOf = usdnr.balanceOf(user);
        // here the transaction should reverts since the reserve is not yet reached
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(usdnr), usdnrBalanceOf - 1, usdnrBalanceOf
            )
        );
        usdnr.unwrap(usdnrBalanceOf, user);

        // mint more than the reserve, then give the yield to the admin
        usdn.mint(address(usdnr), usdnr.RESERVE() * 2);
        usdnr.withdrawYield();

        uint256 usdnBalanceBeforeUnwrap = usdn.balanceOf(user);
        // the transaction should pass
        usdnr.unwrap(usdnrBalanceOf, user);

        assertEq(usdnr.totalSupply(), 0, "the supply should be 0");
        assertEq(
            usdn.balanceOf(user),
            usdnBalanceBeforeUnwrap + usdnrBalanceOf,
            "the user should have received the same amount"
        );
        assertEq(
            usdn.balanceOf(address(usdnr)),
            usdnr.RESERVE(),
            "after the withdrawal of the yield + full user withdraw, the balance should be 0"
        );
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
