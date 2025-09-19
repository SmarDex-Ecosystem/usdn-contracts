// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `wrapShares` function of `USDNr` contract
contract TestUsdnrWrapShares is UsdnrTokenFixture {
    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), 100 ether);
        usdn.approve(address(usdnr), type(uint256).max);
    }

    /**
     * @custom:scenario Wrap USDN shares to USDNr
     * @custom:when The wrapShares function is called with an amount of USDN shares
     * @custom:then The user balance of USDNr increases by the same amount
     * @custom:then The total supply of USDNr increases by the same amount
     * @custom:then The total wrapped USDN increases by the same amount
     */
    function test_usdnrWrapShares() public {
        uint256 amount = 10 ether;
        uint256 sharesAmount = usdn.convertToShares(amount);
        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 usdnContractBalance = usdn.sharesOf(address(usdnr));

        usdnr.wrapShares(sharesAmount, address(this));

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance + amount, "user USDNr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDNr supply");
        assertEq(usdn.sharesOf(address(usdnr)), usdnContractBalance + sharesAmount, "USDN shares balance in USDNr");
    }

    /**
     * @custom:scenario Wrap USDN shares to another address
     * @custom:when The wrapShares function is called with a recipient address
     * @custom:then The recipient balance of USDNr increases by the amount
     * @custom:and The total supply of USDNr increases by the amount
     * @custom:and The user balance of USDN decreases by the amount
     * @custom:and The total wrapped USDN increases by the amount
     */
    function test_wrapSharesToAnotherAddress() public {
        uint256 amount = 10 ether;
        uint256 sharesAmount = usdn.convertToShares(amount);
        address recipient = address(1);

        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrRecipientBalance = usdnr.balanceOf(recipient);
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();

        uint256 initialUsdnBalance = usdn.sharesOf(address(this));
        uint256 initialUsdnContractBalance = usdn.sharesOf(address(usdnr));

        usdnr.wrapShares(sharesAmount, recipient);

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance, "user USDNr balance");
        assertEq(usdnr.balanceOf(recipient), initialUsdnrRecipientBalance + amount, "recipient USDNr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDNr supply");

        assertEq(
            usdn.sharesOf(address(usdnr)), initialUsdnContractBalance + sharesAmount, "USDN shares balance in USDNr"
        );
        assertEq(usdn.sharesOf(address(this)), initialUsdnBalance - sharesAmount, "user USDN shares balance");
    }

    /**
     * @custom:scenario Revert when the wrapShares function is called with zero amount
     * @custom:when The wrapShares function is called with zero amount
     * @custom:then The transaction should revert with the error {USDNrZeroAmount}
     */
    function test_revertWhen_usdnrWrapZeroAmount() public {
        vm.expectRevert(IUsdnr.USDNrZeroAmount.selector);
        usdnr.wrapShares(0, address(this));
    }
}
