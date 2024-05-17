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

    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooLow() external adminPrank {
        uint256 minLeverage = usdnProtocol.getMinLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(minLeverage - 1);
    }

    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooHigh() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(maxLeverage + 1);
    }

    function test_RevertWhen_setPositionMaxLeverageWithCallerNotTheOwner() external {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rebalancer.setPositionMaxLeverage(maxLeverage - 1);
    }

    function test_setPositionMaxLeverage() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();
        uint256 newMaxLeverage = maxLeverage - 1;

        vm.expectEmit();
        emit PositionMaxLeverageUpdated(newMaxLeverage);
        rebalancer.setPositionMaxLeverage(newMaxLeverage);

        assertEq(rebalancer.getPositionMaxLeverage(), newMaxLeverage, "The max leverage should have been updated");
    }
}
