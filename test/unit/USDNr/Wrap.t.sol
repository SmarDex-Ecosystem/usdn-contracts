// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `wrap` function of the `USDnr` contract
contract TestUsdnrWrap is UsdnrTokenFixture {
    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), 100 ether);
        usdn.approve(address(usdnr), type(uint256).max);
    }

    /**
     * @custom:scenario Wrap USDN to USDnr
     * @custom:when The wrap function is called with an amount of USDN
     * @custom:then The user balance of USDnr increases by the same amount
     * @custom:and The total supply of USDnr increases by the same amount
     * @custom:and The total wrapped USDN increases by the same amount
     */
    function test_wrap() public {
        uint256 amount = 10 ether;
        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnBalance = usdn.balanceOf(address(this));
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 usdnContractBalance = usdn.balanceOf(address(usdnr));

        usdnr.wrap(amount, address(this));

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance + amount, "user USDnr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDnr supply");

        assertEq(usdn.balanceOf(address(usdnr)), usdnContractBalance + amount, "USDN balance in USDnr");
        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - amount, "user USDN balance");
    }

    /**
     * @custom:scenario Wrap USDN to another address
     * @custom:when The wrap function is called with a recipient address
     * @custom:then The recipient balance of USDnr increases by the amount
     * @custom:and The total supply of USDnr increases by the amount
     * @custom:and The user balance of USDN decreases by the amount
     * @custom:and The total wrapped USDN increases by the amount
     */
    function test_wrapToAnotherAddress() public {
        uint256 amount = 10 ether;
        address recipient = address(1);

        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrRecipientBalance = usdnr.balanceOf(recipient);
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();

        uint256 initialUsdnBalance = usdn.balanceOf(address(this));
        uint256 initialUsdnContractBalance = usdn.balanceOf(address(usdnr));

        usdnr.wrap(amount, recipient);

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance, "user USDnr balance");
        assertEq(usdnr.balanceOf(recipient), initialUsdnrRecipientBalance + amount, "recipient USDnr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDnr supply");

        assertEq(usdn.balanceOf(address(usdnr)), initialUsdnContractBalance + amount, "USDN balance in USDnr");
        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - amount, "user USDN balance");
    }

    /**
     * @custom:scenario Revert when the wrap function is called with zero amount
     * @custom:when The wrap function is called with zero amount
     * @custom:then The transaction should revert with the error {USDnrZeroAmount}
     */
    function test_revertWhen_wrapZeroAmount() public {
        vm.expectRevert(IUsdnr.USDnrZeroAmount.selector);
        usdnr.wrap(0, address(this));
    }

    /**
     * @custom:scenario Revert when the wrap function is called with zero address as recipient
     * @custom:when The wrap function is called with zero address as recipient
     * @custom:then The transaction should revert with the error {USDnrZeroRecipient}
     */
    function test_revertWhen_wrapRecipientIsZeroAddress() public {
        vm.expectRevert(IUsdnr.USDnrZeroRecipient.selector);
        usdnr.wrap(1, address(0));
    }
}
