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
     * @custom:scenario Check the _positionMaxLeverage value of the rebalancer contract
     * @custom:given A deployed rebalancer contract
     * @custom:when The getPositionMaxLeverage function is called
     * @custom:then The value of the _positionMaxLeverage should be equal to the USDN protocol's max leverage
     */
    function test_getPositionMaxLeverage() public {
        assertEq(rebalancer.getPositionMaxLeverage(), usdnProtocol.getMaxLeverage());
    }

    /**
     * @custom:scenario _positionMaxLeverage is higher than the max leverage of the USDN protocol
     * @custom:given A deployed rebalancer contract with a max leverage higher than the USDN protocol
     * @custom:when The getPositionMaxLeverage function is called
     * @custom:then The returned value should be equal to the USDN protocol's max leverage
     */
    function test_getPositionMaxLeverageWhenHigherThanProtocol() public {
        // Sanity check
        assertEq(
            rebalancer.getPositionMaxLeverage(),
            usdnProtocol.getMaxLeverage(),
            "Both max leverage values should be equal for this test to work"
        );

        uint256 protocolMaxLeverage = usdnProtocol.getMaxLeverage() - 1;
        vm.prank(ADMIN);
        usdnProtocol.setMaxLeverage(protocolMaxLeverage);

        assertEq(
            rebalancer.getPositionMaxLeverage(),
            usdnProtocol.getMaxLeverage(),
            "The max leverage of the USDN protocol should have been returned"
        );
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
}
