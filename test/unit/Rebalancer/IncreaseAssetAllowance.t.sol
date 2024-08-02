// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { RebalancerFixture } from "./utils/Fixtures.sol";

/// @custom:feature The `increaseAssetAllowance` function of the Rebalancer
contract TestRebalancerIncreaseAssetAllowance is RebalancerFixture {
    function setUp() public {
        super._setUp();
    }

    /**
     * @custom:scenario Increase the allowance of the protocol manually
     * @custom:given The initial allowance of the USDN protocol to transfer assets owned by the Rebalancer is 1 ether
     * @custom:when The allowance is increased by 1 ether
     * @custom:then The allowance becomes 2 ether
     * @custom:when The allowance is increased further by (uint256.max - 2 ether)
     * @custom:then The final allowance is uint256.max
     */
    function test_increaseAssetAllowance() public {
        vm.prank(address(rebalancer));
        wstETH.approve(address(usdnProtocol), 1 ether);

        assertEq(wstETH.allowance(address(rebalancer), address(usdnProtocol)), 1 ether, "initial allowance");

        rebalancer.increaseAssetAllowance(1 ether);

        assertEq(
            wstETH.allowance(address(rebalancer), address(usdnProtocol)), 2 ether, "allowance after adding 1 ether"
        );

        rebalancer.increaseAssetAllowance(type(uint256).max - 2 ether);

        assertEq(wstETH.allowance(address(rebalancer), address(usdnProtocol)), type(uint256).max, "final allowance");
    }
}
