// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { UsdnrTokenFixture } from "./utils/Fixtures.sol";

import { IUsdnr } from "../../../src/interfaces/Usdn/IUsdnr.sol";

/// @custom:feature The `depositShares` function of `USDnr` contract
contract TestUsdnrDepositShares is UsdnrTokenFixture {
    function setUp() public override {
        super.setUp();

        usdn.mint(address(this), 100 ether);
        usdn.approve(address(usdnr), type(uint256).max);
    }

    /**
     * @custom:scenario Deposit USDN shares to USDnr
     * @custom:when The depositShares function is called with an amount of USDN shares
     * @custom:then The user balance of USDnr increases by the same amount
     * @custom:then The total supply of USDnr increases by the same amount
     * @custom:then The total deposited USDN increases by the same amount
     */
    function test_usdnrDepositShares() public {
        uint256 amount = 10 ether;
        uint256 sharesAmount = usdn.convertToShares(amount);
        uint256 previewedAmount = usdnr.previewDepositShares(sharesAmount);

        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();
        uint256 usdnContractBalance = usdn.sharesOf(address(usdnr));

        vm.expectEmit();
        emit IERC20.Transfer(address(0), address(this), amount);
        uint256 wrappedAmount = usdnr.depositShares(sharesAmount, address(this));

        assertEq(wrappedAmount, amount, "wrapped USDN amount");
        assertEq(wrappedAmount, previewedAmount, "previewed wrapped USDN amount");

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance + amount, "user USDnr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDnr supply");
        assertEq(usdn.sharesOf(address(usdnr)), usdnContractBalance + sharesAmount, "USDN shares balance in USDnr");
    }

    /**
     * @custom:scenario Deposit USDN shares to another address
     * @custom:when The depositShares function is called with a recipient address
     * @custom:then The recipient balance of USDnr increases by the amount
     * @custom:and The total supply of USDnr increases by the amount
     * @custom:and The user balance of USDN decreases by the amount
     * @custom:and The total deposited USDN increases by the amount
     */
    function test_depositSharesToAnotherAddress() public {
        uint256 amount = 10 ether;
        uint256 sharesAmount = usdn.convertToShares(amount);
        uint256 previewedAmount = usdnr.previewDepositShares(sharesAmount);
        address recipient = address(1);

        uint256 initialUsdnrBalance = usdnr.balanceOf(address(this));
        uint256 initialUsdnrRecipientBalance = usdnr.balanceOf(recipient);
        uint256 initialUsdnrTotalSupply = usdnr.totalSupply();

        uint256 initialUsdnBalance = usdn.sharesOf(address(this));
        uint256 initialUsdnContractBalance = usdn.sharesOf(address(usdnr));

        vm.expectEmit();
        emit IERC20.Transfer(address(0), recipient, amount);
        uint256 mintedAmount = usdnr.depositShares(sharesAmount, recipient);

        assertEq(mintedAmount, amount, "deposited USDN amount");
        assertEq(mintedAmount, previewedAmount, "previewed deposited USDN amount");

        assertEq(usdnr.balanceOf(address(this)), initialUsdnrBalance, "user USDnr balance");
        assertEq(usdnr.balanceOf(recipient), initialUsdnrRecipientBalance + amount, "recipient USDnr balance");
        assertEq(usdnr.totalSupply(), initialUsdnrTotalSupply + amount, "total USDnr supply");

        assertEq(
            usdn.sharesOf(address(usdnr)), initialUsdnContractBalance + sharesAmount, "USDN shares balance in USDnr"
        );
        assertEq(usdn.sharesOf(address(this)), initialUsdnBalance - sharesAmount, "user USDN shares balance");
    }

    /**
     * @custom:scenario Revert when the depositShares function is called with zero amount
     * @custom:when The depositShares function is called with zero amount
     * @custom:then The transaction should revert with the error {USDnrZeroAmount}
     */
    function test_revertWhen_usdnrDepositZeroAmount() public {
        vm.expectRevert(IUsdnr.USDnrZeroAmount.selector);
        usdnr.depositShares(0, address(this));
    }

    /**
     * @custom:scenario Revert when the depositShares function is called with shares that convert to zero USDN
     * @custom:when The depositShares function is called with non-zero shares that convert to zero USDN
     * @custom:then The transaction should revert with the error {USDnrZeroAmount}
     */
    function test_revertWhen_usdnrDepositSharesConvertingToZeroUsdn() public {
        // get the number of shares that convert to 0 wei of USDN
        uint256 sharesAmount = (usdn.convertToShares(1) - 1) / 2;
        assertEq(usdn.convertToTokens(sharesAmount), 0, "shares convert to 0 USDN");
        assertGt(sharesAmount, 0, "shares amount must be greater than 0");

        vm.expectRevert(IUsdnr.USDnrZeroAmount.selector);
        usdnr.depositShares(sharesAmount, address(this));
    }

    /**
     * @custom:scenario Revert when the depositShares function is called with zero address as recipient
     * @custom:when The depositShares function is called with zero address as recipient
     * @custom:then The transaction should revert with the error {USDnrZeroRecipient}
     */
    function test_revertWhen_usdnrDepositSharesToZeroAddress() public {
        vm.expectRevert(IUsdnr.USDnrZeroRecipient.selector);
        usdnr.depositShares(1, address(0));
    }
}
