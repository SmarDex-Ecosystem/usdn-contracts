// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, PYTH_STETH_USD } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction, PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validating two positions with Pyth prices at the same time
 * @custom:background Given a forked ethereum mainnet chain
 */
contract ForkUsdnProtocolValidateTwoPosTest is UsdnProtocolBaseIntegrationFixture {
    uint256 securityDepositValue;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labelled `Fork`
        _setUp(params);
        securityDepositValue = protocol.getSecurityDepositValue();
    }

    /**
     * @custom:scenario Validate two new positions in a single transaction by providing a second price signature
     * @custom:given Two pending open position actions from different users are awaiting confirmation
     * @custom:and The validation deadline has elapsed
     * @custom:when The second user submits the price signatures for his transaction and the first user's transaction
     * @custom:then Both pending actions get validated
     */
    function test_ForkFFIValidateTwoPos() public {
        // Setup 2 pending actions
        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 10 ether }("");
        require(success, "USER_1 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        uint256 ethValue =
            oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) + securityDepositValue;

        protocol.initiateOpenPosition{ value: ethValue }(1 ether, 1000 ether, "", EMPTY_PREVIOUS_DATA);
        uint256 ts1 = block.timestamp;
        vm.stopPrank();
        skip(30);
        vm.startPrank(USER_2);
        (success,) = address(wstETH).call{ value: 10 ether }("");
        require(success, "USER_2 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition{ value: ethValue }(1 ether, 1000 ether, "", EMPTY_PREVIOUS_DATA);
        uint256 ts2 = block.timestamp;
        vm.stopPrank();

        // Wait
        skip(2 hours);

        // Second user tries to validate their action
        (,,,, bytes memory data1) = getHermesApiSignature(PYTH_STETH_USD, ts1 + oracleMiddleware.getValidationDelay());
        uint256 data1Fee = oracleMiddleware.validationCost(data1, ProtocolAction.ValidateOpenPosition);
        (,,,, bytes memory data2) = getHermesApiSignature(PYTH_STETH_USD, ts2 + oracleMiddleware.getValidationDelay());
        uint256 data2Fee = oracleMiddleware.validationCost(data2, ProtocolAction.ValidateOpenPosition);
        bytes[] memory previousData = new bytes[](1);
        previousData[0] = data1;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;
        vm.prank(USER_2);
        protocol.validateOpenPosition{ value: data1Fee + data2Fee }(
            data2, PreviousActionsData(previousData, rawIndices)
        );
        // No more pending action
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "pending actions length");
        vm.stopPrank();
    }
}
