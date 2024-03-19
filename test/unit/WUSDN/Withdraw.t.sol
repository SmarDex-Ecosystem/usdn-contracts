// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `withdraw` function of `WUSDN`
 * @custom:background  Given this contract has the MINTER_ROLE and mint tokens to contract
 * and the contract has deposited 100 usdn in wusdn contract
 */
contract TestWusdnWithdraw is WusdnTokenFixture {
    uint256 internal INITIAL_USDN_DEPOSIT;

    function setUp() public override {
        super.setUp();
        INITIAL_USDN_DEPOSIT = 100 * oneUSDN;

        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(INITIAL_USDN_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario Test the withdraw function
     * @custom:given The contract has deposited 100 usdn
     * @custom:when The contract initiates a withdraw of 1 usdn
     * @custom:then The contract's balance increases by 1 usdn
     * @custom:then The contract's share of wusdn decreases by the expected amount
     * @custom:then The total supply of wusdn decreases by the expected amount
     */
    function test_withdraw_to_wusdn() public {
        uint256 shareBeforeWithdraw = wusdn.totalSupply();
        uint256 shares = wusdn.previewWithdraw(oneUSDN);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(address(this));
        uint256 shareContractBeforeWithdraw = wusdn.balanceOf(address(this));
        wusdn.withdraw(oneUSDN, address(this), address(this));
        assertEq(usdn.balanceOf(address(this)) - balanceBeforeWithdraw, oneUSDN, "usdn balance");
        assertEq(usdn.balanceOf(address(wusdn)), INITIAL_USDN_DEPOSIT - oneUSDN, "usdn balance of wusdn");
        assertEq(shareContractBeforeWithdraw - wusdn.balanceOf(address(this)), shares, "wusdn share");
        assertEq(shareBeforeWithdraw, wusdn.totalSupply() + shares, "wusdn total shares");
    }

    /**
     * @custom:scenario Test the withdraw function
     * @custom:given The contract has deposited 100 usdn
     * @custom:when The user initiates a withdraw of 1 usdn on behalf of the contract
     * @custom:then The contract's balance increases by 1 usdn
     * @custom:then The contract's share of wusdn decreases by the expected amount
     * @custom:then The total supply of wusdn decreases by the expected amount
     */
    function test_withdraw_from_user_to_wusdn() public {
        wusdn.approve(USER_1, type(uint256).max);
        assertEq(wusdn.allowance(address(this), USER_1), type(uint256).max, "test");
        vm.startPrank(USER_1);
        uint256 shareBeforeWithdraw = wusdn.totalSupply();
        uint256 shares = wusdn.previewWithdraw(oneUSDN);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(address(this));
        uint256 shareContractBeforeWithdraw = wusdn.balanceOf(address(this));
        wusdn.withdraw(oneUSDN, address(this), address(this));
        assertEq(usdn.balanceOf(address(this)) - balanceBeforeWithdraw, oneUSDN, "usdn balance");
        assertEq(usdn.balanceOf(address(wusdn)), INITIAL_USDN_DEPOSIT - oneUSDN, "usdn balance of wusdn");
        assertEq(shareContractBeforeWithdraw - wusdn.balanceOf(address(this)), shares, "wusdn share");
        assertEq(shareBeforeWithdraw, wusdn.totalSupply() + shares, "wusdn total shares");
        vm.stopPrank();
    }

    /**
     * @custom:scenario Test the withdraw function
     * @custom:given The contract has deposited 100 usdn
     * @custom:when The contract initiates a withdraw of 0 usdn
     * @custom:then The contract's balance increases by 0 usdn
     * @custom:then The contract's share of wusdn decreases by the expected amount
     * @custom:then The total supply of wusdn decreases by the expected amount
     */
    function test_withdraw_zero_to_wusdn() public {
        uint256 shareBeforeWithdraw = wusdn.totalSupply();
        uint256 shares = wusdn.previewWithdraw(0);
        uint256 balanceBeforeWithdraw = usdn.balanceOf(address(this));
        uint256 shareContractBeforeWithdraw = wusdn.balanceOf(address(this));
        wusdn.withdraw(0, address(this), address(this));
        assertEq(usdn.balanceOf(address(this)) - balanceBeforeWithdraw, 0, "usdn balance");
        assertEq(usdn.balanceOf(address(wusdn)), INITIAL_USDN_DEPOSIT, "usdn balance of wusdn");
        assertEq(shareContractBeforeWithdraw - wusdn.balanceOf(address(this)), shares, "wusdn share");
        assertEq(shareBeforeWithdraw, wusdn.totalSupply() + shares, "wusdn total shares");
    }

    /**
     * @custom:scenario Test the withdraw function with insufficient balance
     * @custom:given A contract with 100 usdn deposited in wusdn
     * @custom:when The contract initiates a withdraw of 101 usdn
     * @custom:then The transaction reverts with the `ERC4626ExceededMaxWithdraw` error
     */
    function test_RevertWhen_withdrawInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxWithdraw.selector, address(this), 101 * oneUSDN, INITIAL_USDN_DEPOSIT
            )
        );
        wusdn.withdraw(101 * oneUSDN, address(this), address(this));
    }

    /**
     * @custom:scenario Test the withdraw function with insufficient balance
     * @custom:given A contract with 100 usdn deposited in wusdn
     * @custom:when The contract initiates a withdraw of 50 USDN
     * @custom:then The transaction reverts with the `ERC4626ExceededMaxWithdraw` error
     */
    function test_RevertWhen_withdrawFromUserInsufficientBalance() public {
        wusdn.approve(USER_1, oneUSDN);
        uint256 shares = wusdn.previewWithdraw(50 * oneUSDN);
        assertEq(wusdn.allowance(address(this), USER_1), oneUSDN, "test");
        vm.startPrank(USER_1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, USER_1, oneUSDN, shares)
        );
        wusdn.withdraw(50 * oneUSDN, address(this), address(this));
    }
}
