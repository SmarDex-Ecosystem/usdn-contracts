// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @custom:feature The `deposit` function of `WUSDN`
 * @custom:background  Given this contract has the MINTER_ROLE and mint tokens to USER_1
 */
contract TestWusdnDeposit is UsdnTokenFixture {
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
    }

    /**
     * @custom:scenario Test deposit function
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The test_deposit function is called
     * @custom:then The deposit is successful
     */
    function test_deposit_to_wusdn() public {
        uint256 shares = wusdn.previewDeposit(oneUSDN);
        uint256 balanceBeforeDeposit = usdn.balanceOf(address(this));
        uint256 shareBeforeDeposit = wusdn.balanceOf(address(this));
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(oneUSDN, address(this));
        assertEq(balanceBeforeDeposit - usdn.balanceOf(address(this)), oneUSDN, "usdn balance of USER_1");
        assertEq(usdn.balanceOf(address(wusdn)), oneUSDN, "usdn balance of wusdn");
        assertEq(wusdn.balanceOf(address(this)) - shareBeforeDeposit, shares, "wusdn share of USER_1");
        assertEq(wusdn.totalSupply(), shares, "wusdn total shares");
    }

    /**
     * @custom:scenario Test deposit function
     * @custom:given The user has initiated a deposit
     * @custom:and The validation deadline has elapsed
     * @custom:when The test_deposit function is called
     * @custom:then The deposit is successful
     */
    function test_deposit_zero_to_wusdn() public {
        uint256 shares = wusdn.previewDeposit(0);
        uint256 balanceBeforeDeposit = usdn.balanceOf(address(this));
        uint256 shareBeforeDeposit = wusdn.balanceOf(address(this));
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(0, address(this));
        assertEq(balanceBeforeDeposit - usdn.balanceOf(address(this)), 0, "usdn balance of USER_1");
        assertEq(usdn.balanceOf(address(wusdn)), 0, "usdn balance of wusdn");
        assertEq(wusdn.balanceOf(address(this)) - shareBeforeDeposit, shares, "wusdn share of USER_1");
        assertEq(wusdn.totalSupply(), shares, "wusdn total shares");
    }

    /**
     * @custom:scenario Test the withdraw function with insufficient balance
     * @custom:given A user with 100 USDN deposited in wusdn
     * @custom:when The user approve 2000 USDN and initiates a withdraw of 2000 USDN
     * @custom:then The transaction reverts with the `ERC20InsufficientBalance` error
     */
    function test_RevertWhen_depositInsufficientBalance() public {
        usdn.approve(address(wusdn), 2000 * oneUSDN);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), 100 * oneUSDN, 2000 * oneUSDN
            )
        );
        wusdn.deposit(2000 * oneUSDN, address(this));
    }
}
