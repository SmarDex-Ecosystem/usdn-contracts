// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IVerifierFeeManager } from "../Middlewares/utils/MockStreamVerifierProxy.sol";

/**
 * @custom:feature The Chainlink data streams fee manager for different states.
 * @custom:background The protocol
 */
contract TestFeeManagerStates is UsdnProtocolBaseIntegrationFixture {
    uint256 securityDeposit;

    function setUp() external {
        _setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100 ether, address(protocol), type(uint256).max);

        securityDeposit = protocol.getSecurityDepositValue();
    }

    function test_verifierWithFeeManagerNoDiscount() external {
        uint256 validationCost = oracleMiddleware.validationCost(payload, ProtocolAction.InitiateOpenPosition);
        assertGt(validationCost, 0, "The data streams validation cost must be positive");

        _initiatePosition(validationCost + securityDeposit);
    }

    function test_verifierWithFeeManagerAndFullDiscount() external {
        address nativeToken = mockFeeManager.i_nativeAddress();
        mockFeeManager.updateSubscriberDiscount(address(oracleMiddleware), report.feedId, nativeToken, 1e18);

        _initiatePosition(securityDeposit);
    }

    function test_verifierWithoutFeeManager() external {
        mockStreamVerifierProxy.setFeeManager(IVerifierFeeManager(address(0)));

        _initiatePosition(securityDeposit);
    }

    function _initiatePosition(uint256 initiateValue) internal {
        (bool success,) = protocol.initiateOpenPosition{ value: initiateValue }(
            2 ether,
            params.initialLiqPrice,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            payload,
            EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "The open position must be initiated");
    }

    receive() external payable {
        revert("Refund is not allowed");
    }
}
