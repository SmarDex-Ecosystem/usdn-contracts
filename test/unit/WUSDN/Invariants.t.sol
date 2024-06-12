// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature Invariants of `WUSDN`
 * @custom:background Given four users that can mint tokens to themselves, burn their balance of tokens,
 * and transfer to other users. Follow invariants in Wusdn
 */
contract TestWusdnInvariants is WusdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.approve(address(wusdn), type(uint256).max);

        targetContract(address(wusdn));
        bytes4[] memory wusdnSelectors = new bytes4[](6);
        // WUSDN functions
        wusdnSelectors[0] = wusdn.wrapTest.selector;
        wusdnSelectors[1] = wusdn.unwrapTest.selector;
        wusdnSelectors[2] = wusdn.transferTest.selector;
        // USDN functions
        wusdnSelectors[3] = wusdn.usdnMintTest.selector;
        wusdnSelectors[4] = wusdn.usdnTransferTest.selector;
        wusdnSelectors[5] = wusdn.usdnBurnTest.selector;
        targetSelector(FuzzSelector({ addr: address(wusdn), selectors: wusdnSelectors }));

        targetSender(USER_1);
        targetSender(USER_2);
        targetSender(USER_3);
        targetSender(USER_4);
    }

    /**
     * @custom:scenario Check that the contract have the expected number of total assets
     */
    function invariant_totalAssetsSum() public {
        // assertEq(usdn.balanceOf(address(wusdn)), wusdn.previewUnwrap(wusdn.totalSupply()), "total assets");
        assertEq(usdn.sharesOf(address(wusdn)), wusdn.totalSupply() * 10 ** 18, "total assets");
        // assertEq(usdn.sharesOf(address(wusdn)), wusdn.totalSupply() * wusdn.SHARES_RATIO());
    }
}
