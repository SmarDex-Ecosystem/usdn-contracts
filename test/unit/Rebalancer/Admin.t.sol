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

    /**
     * @custom:scenario Trying to set the max leverage lower than the USDN protocol's value
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when setPositionMaxLeverage is called with this value
     * @custom:then The call reverts with a RebalancerInvalidMaxLeverage error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooLow() external adminPrank {
        uint256 minLeverage = usdnProtocol.getMinLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(minLeverage - 1);
    }

    /**
     * @custom:scenario Trying to set the max leverage lower than the USDN protocol's value
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when setPositionMaxLeverage is called with this value
     * @custom:then The call reverts with a RebalancerInvalidMaxLeverage error
     */
    function test_RevertWhen_setPositionMaxLeverageWithLeverageTooHigh() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(RebalancerInvalidMaxLeverage.selector);
        rebalancer.setPositionMaxLeverage(maxLeverage + 1);
    }

    /**
     * @custom:scenario Trying to set the max leverage from an address that is not the owner
     * @custom:given The caller not being the owner
     * @custom:when setPositionMaxLeverage is called
     * @custom:then The call reverts with an OwnableUnauthorizedAccount error
     */
    function test_RevertWhen_setPositionMaxLeverageWithCallerNotTheOwner() external {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        rebalancer.setPositionMaxLeverage(maxLeverage - 1);
    }

    /**
     * @custom:scenario Setting the max leverage of the rebalancer
     * @custom:given A value lower than the USDN protocol's max leverage
     * @custom:when setPositionMaxLeverage is called with this value
     * @custom:then The value of _positionMaxLeverageIsUpdated is updated
     * @custom:and An PositionMaxLeverageUpdated event is emitted
     */
    function test_setPositionMaxLeverage() external adminPrank {
        uint256 maxLeverage = usdnProtocol.getMaxLeverage();
        uint256 newMaxLeverage = maxLeverage - 1;

        vm.expectEmit();
        emit PositionMaxLeverageUpdated(newMaxLeverage);
        rebalancer.setPositionMaxLeverage(newMaxLeverage);

        assertEq(rebalancer.getPositionMaxLeverage(), newMaxLeverage, "The max leverage should have been updated");
    }
}
