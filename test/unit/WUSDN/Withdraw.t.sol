// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @custom:feature The `withdraw` function of `WUSDN`
 * @custom:background  Given this contract has the MINTER_ROLE and mint tokens to contract
 * and the user has deposited 1 usdn in wusdn contract
 */
contract TestWusdnWithdraw is UsdnTokenFixture {
    /// Events coming from the OpenZeppelin ERC4626
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    Wusdn wusdn;
    uint256 oneUSDN;

    function setUp() public override {
        super.setUp();

        wusdn = new Wusdn(usdn);

        uint256 decimals = usdn.decimals();
        oneUSDN = 1 * 10 ** decimals;

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(address(this), 100 * oneUSDN);
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(oneUSDN, address(this));
    }

    /**
     * @custom:scenario Test the withdraw function
     * @custom:given The user has deposited 1 usdn
     * @custom:when The user initiates a withdraw of 0.1 usdn
     * @custom:then The user's balance increases by 0.1 usdn
     * @custom:then The user's share of wusdn decreases by the expected amount
     */
    function test_withdraw_to_wusdn() public {
        uint256 shareBeforeWithdraw = wusdn.totalSupply();
        uint256 shares = wusdn.previewWithdraw(oneUSDN / 10);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(address(this));
        uint256 shareUser1BeforeWithdraw = wusdn.balanceOf(address(this));
        wusdn.withdraw(oneUSDN / 10, address(this), address(this));
        assertEq(usdn.balanceOf(address(this)) - balanceBeforeWithdraw, oneUSDN / 10, "usdn balance");
        assertEq(usdn.balanceOf(address(wusdn)), oneUSDN - oneUSDN / 10, "usdn balance of wusdn");
        assertEq(shareUser1BeforeWithdraw - wusdn.balanceOf(address(this)), shares, "wusdn share");
        assertEq(shareBeforeWithdraw, wusdn.totalSupply() + shares, "wusdn total shares");
    }

    /**
     * @custom:scenario Test the withdraw function
     * @custom:given The user has deposited 1 usdn
     * @custom:when The user initiates a withdraw of 0 usdn
     * @custom:then The user's balance increases by 0 usdn
     * @custom:then The user's share of wusdn decreases by the expected amount
     */
    function test_withdraw_zero_to_wusdn() public {
        uint256 shareBeforeWithdraw = wusdn.totalSupply();
        uint256 shares = wusdn.previewWithdraw(0);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(address(this));
        uint256 shareUser1BeforeWithdraw = wusdn.balanceOf(address(this));
        wusdn.withdraw(0, address(this), address(this));
        assertEq(usdn.balanceOf(address(this)) - balanceBeforeWithdraw, 0, "usdn balance");
        assertEq(usdn.balanceOf(address(wusdn)), oneUSDN, "usdn balance of wusdn");
        assertEq(shareUser1BeforeWithdraw - wusdn.balanceOf(address(this)), shares, "wusdn share");
        assertEq(shareBeforeWithdraw, wusdn.totalSupply() + shares, "wusdn total shares");
    }

    /**
     * @custom:scenario Test the withdraw function with insufficient balance
     * @custom:given A user with 1 USDN deposited in wusdn
     * @custom:when The user initiates a withdraw of 2 USDN
     * @custom:then The transaction reverts with the `ERC4626ExceededMaxWithdraw` error
     */
    function test_RevertWhen_withdrawInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626ExceededMaxWithdraw.selector, address(this), 2 * oneUSDN, oneUSDN)
        );
        wusdn.withdraw(2 * oneUSDN, address(this), address(this));
    }
}
