// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2, Test } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature Invariants of `WUSDN`
 * @custom:background  Given four users that can mint tokens to themselves, burn their balance of tokens, and transfer
 *  to other users. Fallow invariants in Wusdn
 */
contract TestWusdnInvariants is WusdnTokenFixture {
    uint256 internal constant INITIAL_WUSDN_DEPOSIT = 1 ether;

    function setUp() public override {
        super.setUp();
        usdn.approve(address(wusdn), type(uint256).max);

        targetContract(address(usdn));
        bytes4[] memory usdnSelectors = new bytes4[](4);
        usdnSelectors[0] = usdn.rebaseTest.selector;
        usdnSelectors[1] = usdn.mintTest.selector;
        usdnSelectors[2] = usdn.burnTest.selector;
        usdnSelectors[3] = usdn.transferTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: usdnSelectors }));
        targetContract(address(wusdn));
        bytes4[] memory wusdnSelectors = new bytes4[](2);
        wusdnSelectors[0] = wusdn.depositTest.selector;
        wusdnSelectors[1] = wusdn.withdrawTest.selector;
        targetSelector(FuzzSelector({ addr: address(wusdn), selectors: wusdnSelectors }));
    }

    /**
     * @custom:scenario Check that the sum of the user shares is equal to the total shares
     */
    function invariant_sumOfSharesBalancesTotalSupply() public {
        uint256 sum =
            wusdn.balanceOf(USER_1) + wusdn.balanceOf(USER_2) + wusdn.balanceOf(USER_3) + wusdn.balanceOf(USER_4);
        assertEq(wusdn.totalSupply(), sum, "total shares");
    }

    /**
     * @custom:scenario Check that the sum of the user shares is equal to the total shares
     */
    function invariant_usdnShareBalanceOfWusdn() public {
        assertEq(usdn.convertToTokens(wusdn.totalSupply()), usdn.sharesOf(address(wusdn)), "total shares");
    }
}
