// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { USER_1, USER_2, USER_3 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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

    function test_validationTwoPendingActionsWithBothOracles() public {
        uint256 initialTimestamp = block.timestamp;
        // create a pending deposit
        mockChainlinkOnChain.setLastPublishTime(initialTimestamp);
        vm.prank(USER_1);
        protocol.initiateDeposit{ value: securityDeposit }(2 ether, USER_1, USER_1, NO_PERMIT2, "", EMPTY_PREVIOUS_DATA);
        // create a pending open position a bit later
        skip(protocol.getOnChainValidationDeadline() / 2);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        vm.prank(USER_2);
        protocol.initiateOpenPosition{ value: securityDeposit }(
            2 ether, params.initialPrice / 2, USER_2, USER_2, NO_PERMIT2, "", EMPTY_PREVIOUS_DATA
        );
        // create a pending deposit a bit later
        vm.warp(initialTimestamp + protocol.getOnChainValidationDeadline() + 1);
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);
        // prepare pyth for validation
        (, int256 ethPrice,,,) = mockChainlinkOnChain.latestRoundData();
        mockPyth.setLastPublishTime(block.timestamp + oracleMiddleware.getValidationDelay());
        mockPyth.setPrice(int24(ethPrice));
        vm.prank(USER_3);
        protocol.initiateDeposit{ value: securityDeposit }(2 ether, USER_3, USER_3, NO_PERMIT2, "", EMPTY_PREVIOUS_DATA);
        // wait until the first and third are actionable
        vm.warp(initialTimestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidationDeadline() + 1);

        // a user who creates a new position will need to validate the first actionable pending actions (on-chain
        // oracle)
        (Types.PendingAction[] memory actions, uint128[] memory rawIndices) =
            protocol.getActionablePendingActions(address(this));
        assertEq(actions.length, 3, "actions length");
        bytes[] memory priceData = new bytes[](3);
        priceData[2] = MOCK_PYTH_DATA;
        Types.PreviousActionsData memory previousData =
            Types.PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });
        uint256 validationCost = oracleMiddleware.validationCost(priceData[2], Types.ProtocolAction.ValidateDeposit);
        protocol.initiateOpenPosition{ value: securityDeposit + validationCost }(
            2 ether, params.initialPrice / 2, address(this), payable(this), NO_PERMIT2, "", previousData
        );
    }

    receive() external payable { }
}
