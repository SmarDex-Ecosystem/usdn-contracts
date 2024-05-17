// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";

/**
 * @custom:feature The setter and getter functions of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancer is RebalancerFixture {
    function setUp() public {
        super._setUp();
    }

    /**
     * @custom:scenario Check the _asset value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The getAsset function is called
     * @custom:then The value of the asset should be equal to the USDN protocol asset contract
     */
    function test_asset() public {
        assertEq(address(usdnProtocol.getAsset()), address(rebalancer.getAsset()));
    }

    /**
     * @custom:scenario Check the _usdnProtocol value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The getUsdnProtocol function is called
     * @custom:then The value of the _usdnProtocol should be equal to the protocol contract address
     */
    function test_usdnProtocol() public {
        assertEq(address(usdnProtocol), address(rebalancer.getUsdnProtocol()));
    }

    /**
     * @custom:scenario Check the _positionVersion value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The getPositionVersion function is called
     * @custom:then The value of the _positionVersion should be equal to 0
     */
    function test_positionVersion() public {
        assertEq(0, rebalancer.getPositionVersion());
    }

    /**
     * @custom:scenario Check the _minAssetDeposit value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The getMinAssetDeposit function is called
     * @custom:then The value of the _minAssetDeposit should be equal to the protocol _minLongPosition
     */
    function test_minAssetDeposit() public {
        assertEq(usdnProtocol.getMinLongPosition(), rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario Set of the _minAssetDeposit value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called with a valid new value
     * @custom:then The value should have changed
     */
    function test_setMinAssetDeposit() public {
        uint256 newValue = usdnProtocol.getMinLongPosition() + 1 ether;

        vm.prank(ADMIN);
        vm.expectEmit();
        emit MinAssetDepositUpdated(newValue);
        rebalancer.setMinAssetDeposit(newValue);
        assertEq(newValue, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario Try to set the _minAssetDeposit value to an amount lower than the USDN Protocol
     * getMinLongPosition
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called with a value lower than protocol.getMinLongPosition()
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_setMinAssetDeposit_Invalid() public {
        uint256 minLimit = usdnProtocol.getMinLongPosition();
        assertGt(minLimit, 0, "the minimum of the protocol should be greater than 0");

        vm.prank(ADMIN);
        vm.expectRevert(RebalancerInvalidMinAssetDeposit.selector);
        rebalancer.setMinAssetDeposit(minLimit - 1);
    }

    /**
     * @custom:scenario Try to set the _minAssetDeposit value without being the admin
     * @custom:given A deployed rebalancer contract
     * @custom:when The setter is called by an unauthorized account
     * @custom:then The transaction reverts
     */
    function test_RevertWhen_setMinAssetDeposit_NotAdmin() public {
        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.setMinAssetDeposit(1);
    }
}
