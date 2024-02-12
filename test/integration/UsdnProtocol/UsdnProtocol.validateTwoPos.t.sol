// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, DEPLOYER, PYTH_STETH_USD } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";

contract UsdnProtocolValidateTwoPosTest is UsdnProtocolBaseIntegrationFixture {
    function setUp() public override {
        params = DEFAULT_PARAMS;
        params.fork = true;
        _setUp(params);
    }

    function test_ForkFFIValidateTwoPos() public {
        // Setup 2 pending actions
        vm.startPrank(USER_1);
        (bool success,) = address(WST_ETH).call{ value: 10 ether }("");
        require(success, "USER_1 wstETH mint failed");
        WST_ETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition{ value: wstethMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, 1000 ether, "", ""
        );
        uint256 ts1 = block.timestamp;
        vm.stopPrank();
        skip(30);
        vm.startPrank(USER_2);
        (success,) = address(WST_ETH).call{ value: 10 ether }("");
        require(success, "USER_2 wstETH mint failed");
        WST_ETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition{ value: wstethMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, 1000 ether, "", ""
        );
        uint256 ts2 = block.timestamp;
        vm.stopPrank();

        // Wait
        skip(2 hours);

        // Second user tries to validate their action
        (,,, bytes memory data1) = getHermesApiSignature(PYTH_STETH_USD, ts1 + wstethMiddleware.validationDelay());
        uint256 data1Fee = wstethMiddleware.validationCost(data1, ProtocolAction.ValidateOpenPosition);
        (,,, bytes memory data2) = getHermesApiSignature(PYTH_STETH_USD, ts2 + wstethMiddleware.validationDelay());
        uint256 data2Fee = wstethMiddleware.validationCost(data2, ProtocolAction.ValidateOpenPosition);
        vm.prank(USER_2);
        protocol.validateOpenPosition{ value: data1Fee + data2Fee }(data2, data1);
        // No more pending action
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(0));
        vm.stopPrank();
    }
}
