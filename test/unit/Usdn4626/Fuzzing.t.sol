// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Usdn4626Fixture } from "./utils/Fixtures.sol";

contract TestUsdn4626Fuzzing is Usdn4626Fixture {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_convertToShares(uint256 assets, uint256 divisor) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        assets = bound(assets, 0, usdn.maxTokens());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }
        uint256 shares = usdn4626.convertToShares(assets);
        assertEq(shares, usdn.convertToShares(assets) / 1e18, "USDN.convertToShares");
        assertEq(shares, usdn4626.previewDeposit(assets), "previewDeposit");
    }

    function testFuzz_convertToAssets(uint256 shares, uint256 divisor) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }
        shares = bound(shares, 0, type(uint256).max / 1e18);
        uint256 assets = usdn4626.convertToAssets(shares);
        assertLe(assets, usdn.convertToTokens(shares * 1e18), "USDN.convertToTokens");
        assertApproxEqAbs(assets, usdn.convertToTokens(shares * 1e18), 1, "USDN.convertToTokens 1 wei off max");
        assertLe(assets, usdn4626.previewRedeem(shares), "previewRedeem");
        assertApproxEqAbs(assets, usdn4626.previewRedeem(shares), 1, "previewRedeem 1 wei off max");
    }

    function test_depositZero() public {
        usdn4626.deposit(0, address(this));
    }
}
