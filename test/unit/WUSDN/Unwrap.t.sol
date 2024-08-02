// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WusdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `unwrap` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE and 100 USDN
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnUnwrap is WusdnTokenFixture {
    /// @notice USDN amount before the test
    uint256 public usdnAmount;
    /// @notice WUSDN amount before the test
    uint256 public wusdnAmount;

    function setUp() public override {
        super.setUp();
        usdnAmount = usdn.balanceOf(address(this));
        usdn.approve(address(wusdn), usdnAmount);
        wusdnAmount = wusdn.wrap(usdnAmount);
    }

    /**
     * @custom:scenario Unwrap WUSDN to USDN
     * @custom:given A user with some WUSDN
     * @custom:and All the usdnAmount is wrapped to WUSDN
     * @custom:when The wusdnAmount/ 2 is unwrapped from WUSDN
     * @custom:then The user should have usdnAmount/ 2 USDN
     * @custom:and wusdnAmount / 2 WUSDN
     */
    function test_unwrap() public {
        vm.expectEmit(address(wusdn));
        emit Unwrap(address(this), address(this), wusdnAmount / 2, usdnAmount / 2);
        wusdn.unwrap(wusdnAmount / 2);

        assertEq(wusdn.totalUsdnBalance(), usdnAmount / 2, "total USDN supply in WUSDN");
        assertEq(wusdn.totalSupply(), wusdnAmount / 2, "total wrapped supply");
        assertEq(usdn.balanceOf(address(this)), usdnAmount / 2, "USDN balance");
        assertEq(wusdn.balanceOf(address(this)), wusdnAmount / 2, "WUSDN balance");
    }

    /**
     * @custom:scenario Unwrap WUSDN to USDN
     * @custom:given A user with some WUSDN
     * @custom:and All the usdnAmount is wrapped to WUSDN
     * @custom:when The wusdnAmount is unwrapped from WUSDN
     * @custom:and The `to` parameter is USER_1
     * @custom:then The user should have usdnAmount USDN
     * @custom:and wusdnAmount WUSDN
     */
    function test_unwrapTo() public {
        uint256 initialBalance = usdn.balanceOf(USER_1);
        vm.expectEmit(address(wusdn));
        emit Unwrap(address(this), USER_1, wusdnAmount, usdnAmount);
        wusdn.unwrap(wusdnAmount, USER_1);

        assertEq(wusdn.totalUsdnBalance(), 0, "total USDN balance of WUSDN");
        assertEq(wusdn.totalSupply(), 0, "total supply should be 0");
        assertEq(usdn.balanceOf(USER_1), usdnAmount + initialBalance, "USDN balance");
        assertEq(wusdn.balanceOf(USER_1), 0, "WUSDN balance");
    }
}
