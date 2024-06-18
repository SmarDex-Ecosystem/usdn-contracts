// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { USER_1, USER_2, USER_3, USER_4 } from "../../utils/Constants.sol";
import { WusdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Invariants of `WUSDN`
 * @custom:background Given four users that can mint tokens for themselves, burn their balance of tokens,
 * and transfer to other users
 */
contract TestWusdnInvariants is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.approve(address(wusdn), type(uint256).max);

        targetContract(address(wusdn));

        bytes4[] memory wusdnSelectors = new bytes4[](8);
        // WUSDN functions
        wusdnSelectors[0] = wusdn.wrapTest.selector;
        wusdnSelectors[1] = wusdn.wrapSharesTest.selector;
        wusdnSelectors[2] = wusdn.unwrapTest.selector;
        wusdnSelectors[3] = wusdn.transferTest.selector;
        // USDN functions
        wusdnSelectors[4] = wusdn.usdnMintTest.selector;
        wusdnSelectors[5] = wusdn.usdnTransferTest.selector;
        wusdnSelectors[6] = wusdn.usdnBurnTest.selector;
        wusdnSelectors[7] = wusdn.usdnRebaseTest.selector;

        targetSelector(FuzzSelector({ addr: address(wusdn), selectors: wusdnSelectors }));

        targetSender(USER_1);
        targetSender(USER_2);
        targetSender(USER_3);
        targetSender(USER_4);

        usdn.mint(USER_1, 2500 ether);
        usdn.mint(USER_2, 2500 ether);
        usdn.mint(USER_3, 2500 ether);
        usdn.mint(USER_4, 2500 ether);
    }

    /**
     * @custom:scenario Check that the contract has the expected number of total assets
     */
    function invariant_totalAssetsSum() public {
        assertEq(usdn.balanceOf(address(wusdn)), wusdn.previewUnwrap(wusdn.totalSupply()), "total assets previewUnwrap");
        assertEq(
            usdn.balanceOf(address(wusdn)),
            wusdn.previewUnwrap(
                wusdn.balanceOf(USER_1) + wusdn.balanceOf(USER_2) + wusdn.balanceOf(USER_3) + wusdn.balanceOf(USER_4)
            ),
            "total assets users"
        );
        assertEq(usdn.sharesOf(address(wusdn)), wusdn.totalSupply() * wusdn.SHARES_RATIO(), "total shares");
    }

    /**
     * @custom:scenario Check that the contract has no USDN shares after unwrapping all WUSDN
     */
    function invariant_noSharesAfterUnwrap() public {
        wusdn.unwrapAll();
        assertEq(usdn.sharesOf(address(wusdn)), 0, "total shares after unwrap");
        assertEq(wusdn.totalSupply(), 0, "total supply after unwrap");
    }
}
