// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @custom:feature The admin functions of the rebalancer contract
 * @custom:background Given an rebalancer contract
 */
contract TestRebalancerDepositAssets is RebalancerFixture {
    function setUp() public {
        super._setUp();
    }

    function test_RevertWhen_setMaxLeverageWithLeverageTooLow() external adminPrank {
        uint256 minLeverage = usdnProtocol.getMinLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setMaxLeverage(minLeverage - 1);
    }

    function test_RevertWhen_setMaxLeverageWithLeverageTooHigh() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setMaxLeverage(maxLeverage + 1);
    }

    function test_RevertWhen_setMaxLeverageWithCallerNotTheOwner() external {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rebalancer.setMaxLeverage(maxLeverage - 1);
    }

    function test_setMaxLeverage() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();
        uint256 newMaxLeverage = maxLeverage - 1;

        vm.expectEmit();
        emit PositionMaxLeverageUpdated(newMaxLeverage);
        rebalancer.setMaxLeverage(newMaxLeverage);

        assertEq(rebalancer.getMaxLeverage(), newMaxLeverage, "The max leverage should have been updated");
    }
}
