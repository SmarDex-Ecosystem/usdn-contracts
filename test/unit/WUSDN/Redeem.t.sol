// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature The `redeem` function of `WUSDN`
 * @custom:background Given this contract has the MINTER_ROLE
 * @custom:and The divisor is MAX_DIVISOR
 */
contract TestWusdnRedeem is WusdnTokenFixture {
    /**
     * @custom:scenario redeem usdn to wusdn contract
     * @custom:given 100 usdn are minted to a user
     * @custom:and 30 share is minted in wusdn to a user
     * @custom:and rebased to 0.5x MAX_DIVISOR
     * @custom:when 15 shares are redeemed from wusdn
     * @custom:and The total assets of usdn are 30
     * @custom:and The total supply of wusdn is 15
     */
    function test_redeem() public {
        usdn.approve(address(wusdn), type(uint256).max);

        uint256 mintedShares = 30 ether;
        wusdn.wrap(mintedShares);
        usdn.rebase(usdn.MAX_DIVISOR() / 2);
        uint256 redeemedShares = 15 ether;
        wusdn.unwrap(redeemedShares);
        assertApproxEqAbs(wusdn.totalUsdn(), wusdn.convertToAssets(mintedShares - redeemedShares), 1, "total assets");
        assertEq(wusdn.totalSupply(), mintedShares - redeemedShares, "total supply");
    }
}
