// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @custom:feature The ERC-4626 functions of `WUSDN`
 * @custom:background Given a user with 100 tokens
 */
contract TestWusdnInvariants is UsdnTokenFixture {
    Wusdn wusdn;
    uint256 internal maxDivisor;
    uint256 internal minDivisor;
    uint256 internal constant INITIAL_WUSDN_DEPOSIT = 1 ether;

    function setUp() public override {
        super.setUp();

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(USER_1, 100 ether);
        maxDivisor = usdn.MAX_DIVISOR();
        minDivisor = usdn.MIN_DIVISOR();
        wusdn = new Wusdn(usdn);
        vm.startPrank(USER_1);
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(INITIAL_WUSDN_DEPOSIT, USER_1);
        vm.stopPrank();

        targetContract(address(usdn));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = usdn.rebaseTest.selector;
        selectors[1] = usdn.mintTest.selector;
        selectors[2] = usdn.burnTest.selector;
        selectors[3] = usdn.transferTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: selectors }));
    }

    /**
     * @custom:scenario Check that the contract returns the expected asset managed
     */
    function invariant_asset_wusdn() public {
        assertEq(address(usdn), wusdn.asset(), "asset managed");
    }

    /**
     * @custom:scenario Check that the contract returns the expected supply
     */
    function invariant_deposit_total_wusdn() public {
        wusdn.deposit(1 ether, USER_1);
        wusdn.deposit(1 ether, USER_2);
        wusdn.deposit(1 ether, USER_3);
        wusdn.deposit(1 ether, USER_4);
        uint256 sum =
            wusdn.balanceOf(USER_1) + wusdn.balanceOf(USER_2) + wusdn.balanceOf(USER_3) + wusdn.balanceOf(USER_4);
        assertEq(wusdn.balanceOf(USER_1), sum + INITIAL_WUSDN_DEPOSIT, "total balance");
    }
}
