// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { USER_1, USER_2, USER_3 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validate actionable pending actions via normal user actions and the special dedicated action
 * @custom:background The protocol has 3 pending actions, two of which are actionable
 */
contract TestUsdnProtocolActionablePendingActions is UsdnProtocolBaseIntegrationFixture {
    uint256 internal securityDeposit;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);
        securityDeposit = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(address(this), 1_000_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 1_000_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_2, 1_000_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_3, 1_000_000 ether, address(protocol), type(uint256).max);
        deal(address(sdex), address(this), 1e6 ether);
        deal(address(sdex), USER_1, 1e6 ether);
        deal(address(sdex), USER_2, 1e6 ether);
        deal(address(sdex), USER_3, 1e6 ether);
        sdex.approve(address(protocol), type(uint256).max);
        vm.prank(USER_1);
        sdex.approve(address(protocol), type(uint256).max);
        vm.prank(USER_2);
        sdex.approve(address(protocol), type(uint256).max);
        vm.prank(USER_3);
        sdex.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario A user validates the first actionable pending action while performing a normal action
     * @custom:when The user initiates a new position while providing the required validation information for actionable
     * pending actions
     * @custom:then The first actionable pending action is validated and only one remains
     */
    function test_validatePendingActionByUser() public {
        Types.PreviousActionsData memory previousData = _pendingActionsHelper(); // create 3 positions with 2 being
            // actionable
        // a user who creates a new position will need to validate the first actionable pending actions (on-chain
        // oracle)
        uint256 validationCost =
            oracleMiddleware.validationCost(previousData.priceData[2], Types.ProtocolAction.ValidateDeposit);
        assertEq(validationCost, 1, "validation cost");
        protocol.initiateOpenPosition{ value: securityDeposit + validationCost }(
            2 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            "",
            previousData
        );
        // check that one pending action was validated, only one should remain
        (Types.PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(this), 0, 0);
        assertEq(actions.length, 1, "actions length after");
    }

    /**
     * @custom:scenario A bot validates two actionable pending actions
     * @custom:when The bot validates two actionable pending actions by providing the required validation information
     * @custom:then Both actionable pending actions are validated and none remain
     */
    function test_validateTwoPendingActionsByBot() public {
        Types.PreviousActionsData memory previousData = _pendingActionsHelper(); // create 3 positions with 2 being
            // actionable
        // a bot now validates both actionable pending actions
        uint256 validationCost =
            oracleMiddleware.validationCost(previousData.priceData[2], Types.ProtocolAction.ValidateDeposit);
        assertEq(validationCost, 1, "validation cost");
        protocol.validateActionablePendingActions{ value: validationCost }(previousData, 10);
        // check that both pending actions were validated
        (Types.PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(this), 0, 0);
        assertEq(actions.length, 0, "actions length after");
    }

    /**
     * @custom:scenario The lookahead feature is used to get actionable pending actions which will become actionable
     * @custom:given Three pending actions, the first and third being actionable at block.timestamp
     * @custom:and The second pending action being actionable in 35 minutes
     * @custom:when The `getActionablePendingActions` function is called without a lookahead
     * @custom:then Only the first and third pending actions are returned
     * @custom:when The `getActionablePendingActions` function is called with a lookahead of 35 minutes
     * @custom:then All three pending actions are returned
     */
    function test_getActionablePendingActionsLookAhead() public {
        // create 3 positions with 2 being actionable at block.timestamp
        _pendingActionsHelper();
        // at this moment, only 2 are actionable
        (Types.PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(0), 0, 0);
        assertEq(rawIndices.length, 3, "zero lookahead length"); // 3 but second one is empty
        assertTrue(actions[0].action == Types.ProtocolAction.ValidateDeposit, "zero lookahead first action");
        assertTrue(actions[1].action == Types.ProtocolAction.None, "zero lookahead second action");
        assertTrue(actions[2].action == Types.ProtocolAction.ValidateDeposit, "zero lookahead third action");
        // in 35 minutes, the second action should be actionable
        // the call below will add this one on top of the existing list thanks to the lookahead, so we should get all 3
        // actions
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 35 minutes, 0);
        assertEq(rawIndices.length, 3, "raw indices length");
        assertTrue(actions[0].action == Types.ProtocolAction.ValidateDeposit, "first action");
        assertTrue(actions[1].action == Types.ProtocolAction.ValidateOpenPosition, "second action");
        assertTrue(actions[2].action == Types.ProtocolAction.ValidateDeposit, "third action");
        // check a very high value to make sure everything works
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0), 1e9, 0);
        assertEq(rawIndices.length, 3, "raw indices length");
    }

    /**
     * @notice Helper to setup 3 pending actions, 2 of which are actionable
     * @return previousData The previous actions data needed to validate the pending actions
     */
    function _pendingActionsHelper() internal returns (Types.PreviousActionsData memory) {
        uint256 initialTimestamp = block.timestamp;
        // create a pending deposit
        mockChainlinkOnChain.setLastPublishTime(initialTimestamp);
        vm.prank(USER_1);
        protocol.initiateDeposit{ value: securityDeposit }(
            2 ether, DISABLE_SHARES_OUT_MIN, USER_1, USER_1, type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );
        // create a pending open position a bit later
        skip(protocol.getOnChainValidatorDeadline() / 2);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        vm.prank(USER_2);
        protocol.initiateOpenPosition{ value: securityDeposit }(
            2 ether,
            params.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            USER_2,
            USER_2,
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );
        // create a pending deposit a bit later
        vm.warp(initialTimestamp + protocol.getOnChainValidatorDeadline() + 1);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        // prepare pyth for validation
        (, int256 ethPrice,,,) = mockChainlinkOnChain.latestRoundData();
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int64(ethPrice));
        vm.prank(USER_3);
        protocol.initiateDeposit{ value: securityDeposit }(
            2 ether, DISABLE_SHARES_OUT_MIN, USER_3, USER_3, type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );
        // wait until the first and third are actionable
        vm.warp(initialTimestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1);
        mockChainlinkOnChain.setLatestRoundData(10, ethPrice, block.timestamp, 10);
        uint256 prevRoundTimestamp = initialTimestamp + oracleMiddleware.getLowLatencyDelay() - 10 minutes;
        mockChainlinkOnChain.setRoundData(8, ethPrice, prevRoundTimestamp, prevRoundTimestamp, 8);
        uint256 nextRoundTimestamp = initialTimestamp + oracleMiddleware.getLowLatencyDelay() + 10 minutes;
        mockChainlinkOnChain.setRoundData(9, ethPrice, nextRoundTimestamp, nextRoundTimestamp, 9);

        (Types.PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(this), 0, 0);
        assertEq(actions.length, 3, "actions length before");
        bytes[] memory priceData = new bytes[](3);
        priceData[0] = abi.encode(9); // round ID after the first initiate
        priceData[2] = MOCK_PYTH_DATA;
        Types.PreviousActionsData memory previousData =
            Types.PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });
        return previousData;
    }

    receive() external payable { }
}
