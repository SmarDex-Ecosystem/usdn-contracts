// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IVerifierFeeManager } from "../Middlewares/utils/MockStreamVerifierProxy.sol";

/**
 * @custom:feature The Chainlink data streams fee manager for different states.
 * @custom:background A deployed USDN protocol, an oracle middleware and a data streams proxy verifier.
 */
contract TestFeeManagerStates is UsdnProtocolBaseIntegrationFixture {
    uint256 securityDeposit;

    function setUp() external {
        _setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100 ether, address(protocol), type(uint256).max);

        securityDeposit = protocol.getSecurityDepositValue();
    }

    /**
     * @custom:scenario Tests the `initiateOpenPosition` function without oracle discount.
     * @custom:given A linked fee manager without discount.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     */
    function test_verifierWithFeeManagerNoDiscount() external {
        uint256 validationCost = oracleMiddleware.validationCost(payload, ProtocolAction.InitiateOpenPosition);
        assertGt(validationCost, 0, "The data streams validation cost must be positive");

        _initiatePosition(validationCost + securityDeposit);
    }

    /**
     * @custom:scenario Tests the `initiateOpenPosition` function with oracle full discount.
     * @custom:given A linked fee manager with a full discount set for the middleware.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     */
    function test_verifierWithFeeManagerAndFullDiscount() external {
        address nativeToken = mockFeeManager.i_nativeAddress();
        mockFeeManager.updateSubscriberDiscount(address(oracleMiddleware), report.feedId, nativeToken, 1e18);

        _initiatePosition(securityDeposit);
    }

    /**
     * @custom:scenario Tests the `initiateOpenPosition` function without fee manager.
     * @custom:when The function is called.
     * @custom:then The transaction must be successful.
     */
    function test_verifierWithoutFeeManager() external {
        mockStreamVerifierProxy.setFeeManager(IVerifierFeeManager(address(0)));

        _initiatePosition(securityDeposit);
    }

    /**
     * @dev Initiates an open position though the USDN protocol with a data streams oracle middleware.
     * @param initiateValue The ETH oracle fee value required to initiate an open position.
     */
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

    /// @dev We doesn't accept any refund.
    receive() external payable {
        revert("Refund is not allowed");
    }
}
