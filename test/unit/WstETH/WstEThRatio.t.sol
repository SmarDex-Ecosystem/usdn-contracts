// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { WstEthFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Test functions in `wstEth` focus on ratio
 */
contract TestWstEthRatio is WstEthFixture {
    function setUp() public override {
        super.setUp();
        deal(USER_1, 1 ether);
        stETH.mint(USER_1, 1 ether);
        (bool success,) = payable(wstETH).call{ value: 1 ether }("");
        assertTrue(success);
        wstETH.transfer(USER_1, 1 ether);
    }

    function test_ratio() public {
        assertEq(wstETH.getWstETHByStETH(1 ether), 1 ether);
        assertEq(wstETH.getStETHByWstETH(1 ether), 1 ether);
        assertEq(wstETH.tokensPerStEth(), 1 ether);
        assertEq(wstETH.stEthPerToken(), 1 ether);

        stETH.mint(address(wstETH), 1 ether);

        assertEq(wstETH.getWstETHByStETH(1 ether), 0.5 ether);
        assertApproxEqAbs(wstETH.getStETHByWstETH(1 ether), 2 ether, 1 wei);
        assertEq(wstETH.tokensPerStEth(), 0.5 ether);
        assertApproxEqAbs(wstETH.stEthPerToken(), 2 ether, 1 wei);
    }

    function test_setRatio() public {
        assertEq(wstETH.getWstETHByStETH(1 ether), 1 ether);
        assertEq(wstETH.getStETHByWstETH(1 ether), 1 ether);
        assertEq(wstETH.tokensPerStEth(), 1 ether);
        assertEq(wstETH.stEthPerToken(), 1 ether);

        // increase ratio
        stETH.setStEthPerToken(2 ether, wstETH);

        assertEq(wstETH.getWstETHByStETH(1 ether), 0.5 ether);
        assertEq(wstETH.getStETHByWstETH(1 ether), 2 ether);
        assertEq(wstETH.tokensPerStEth(), 0.5 ether);
        assertEq(wstETH.stEthPerToken(), 2 ether);

        // decrease ratio
        stETH.setStEthPerToken(0.5 ether, wstETH);

        assertApproxEqAbs(wstETH.getWstETHByStETH(1 ether), 2 ether, 2 wei);
        assertApproxEqAbs(wstETH.getStETHByWstETH(1 ether), 0.5 ether, 1 wei);
        assertApproxEqAbs(wstETH.tokensPerStEth(), 2 ether, 2 wei);
        assertApproxEqAbs(wstETH.stEthPerToken(), 0.5 ether, 1 wei);
    }
}
