// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The setter and getter functions of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancer is RebalancerFixture {
    function setUp() public {
        super._setUp();
    }

    /**
     * @custom:scenario An address that is not the USDN protocol sends ether to the rebalancer
     * @custom:given The sender is not the USDN protocol
     * @custom:when Ether is sent to the rebalancer contract
     * @custom:then The call returns false and the bytes of the {RebalancerUnauthorized} error
     */
    function test_RevertWhen_receivingEther() public {
        (bool success, bytes memory data) = address(rebalancer).call{ value: 1 }("");

        assertFalse(success, "The call should have failed");
        assertEq(bytes4(data), RebalancerUnauthorized.selector);
    }

    /**
     * @custom:scenario The USDN protocol sends ether to the rebalancer contract
     * @custom:given The sender is the USDN protocol
     * @custom:when Ether is sent to the rebalancer contract
     * @custom:then The rebalancer's balance is equal to the value sent
     * @custom:and True is returned as the `success` variable
     */
    function test_canReceiveEtherFromUsdnProtocol() public {
        vm.deal(address(usdnProtocol), 1);

        vm.prank(address(usdnProtocol));
        (bool success,) = address(rebalancer).call{ value: 1 }("");

        assertTrue(success, "The call should have been a success");
        assertEq(address(rebalancer).balance, 1, "The rebalancer should have received the ether");
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
