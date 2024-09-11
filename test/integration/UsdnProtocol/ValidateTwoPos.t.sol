// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PYTH_ETH_USD, USER_1, USER_2 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Validating two positions with Pyth prices at the same time
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUsdnProtocolValidateTwoPos is UsdnProtocolBaseIntegrationFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labeled `Fork`
        params.forkWarp = 1_717_452_000; // Mon Jun 03 2024 22:00:00 UTC
        params.forkBlock = 20_014_134;
        _setUp(params);
    }

    /**
     * @custom:scenario Validate two new positions in a single transaction by providing a second price signature
     * @custom:given Two pending open position actions from different users are awaiting confirmation
     * @custom:and The validation deadline has elapsed
     * @custom:when The second user submits the price signatures for his transaction and the first user's transaction
     * @custom:then Both pending actions get validated
     */
    function test_ForkFFIValidateTwoPos() public {
        // setup 2 pending actions
        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 10 ether }("");
        require(success, "USER_1 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        uint256 ethValue = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition)
            + protocol.getSecurityDepositValue();

        protocol.initiateOpenPosition{ value: ethValue }(
            2.5 ether, 1000 ether, protocol.getMaxLeverage(), address(this), USER_1, NO_PERMIT2, "", EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();
        vm.rollFork(block.number + 80 minutes / 12);
        vm.startPrank(USER_2);
        (success,) = address(wstETH).call{ value: 10 ether }("");
        require(success, "USER_2 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        protocol.initiateOpenPosition{ value: ethValue }(
            2.5 ether, 1000 ether, protocol.getMaxLeverage(), address(this), USER_2, NO_PERMIT2, "", EMPTY_PREVIOUS_DATA
        );
        uint256 ts2 = block.timestamp;
        vm.stopPrank();

        // wait to make user1's action is actionable
        skip(20 minutes);

        // user1's position must be validated with chainlink
        // first round ID after the `forkWarp` timestamp + 20 minutes
        bytes memory data1 = abi.encode(uint80(110_680_464_442_257_327_600));
        uint256 data1Fee = oracleMiddleware.validationCost(data1, ProtocolAction.ValidateOpenPosition);
        // user2's position must be validated with a low-latency oracle
        (,,,, bytes memory data2) = getHermesApiSignature(PYTH_ETH_USD, ts2 + oracleMiddleware.getValidationDelay());
        uint256 data2Fee = oracleMiddleware.validationCost(data2, ProtocolAction.ValidateOpenPosition);
        bytes[] memory previousData = new bytes[](1);
        previousData[0] = data1;
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;

        // second user tries to validate their action
        vm.prank(USER_2);
        protocol.validateOpenPosition{ value: data1Fee + data2Fee }(
            USER_2, data2, PreviousActionsData(previousData, rawIndices)
        );
        // no more pending action
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "pending actions length");
        vm.stopPrank();
    }
}
