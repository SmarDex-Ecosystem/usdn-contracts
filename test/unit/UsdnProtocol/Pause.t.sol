// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

/// @custom:feature The pausable functions of the `usdnProtocol`
contract TestUsdnProtocolPausable is UsdnProtocolBaseFixture {
    PositionId internal emptyPosId = PositionId(0, 0, 0);
    address payable internal constant ADDR_ZERO = payable(address(0));
    bytes4 internal pausedErr = PausableUpgradeable.EnforcedPause.selector;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        vm.prank(ADMIN);
        protocol.pause();
        assertTrue(protocol.isPaused(), "The protocol should be paused");
    }

    /**
     * @custom:scenario Call all functions with the `whenNotPaused` modifier
     * @custom:given A paused usdnProtocol
     * @custom:when Each function is called
     * @custom:then Each function should revert with the `EnforcedPause` error
     */
    function test_RevertWhen_callsPausedFunctions() public {
        vm.expectRevert(pausedErr);
        protocol.initiateDeposit(0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateDeposit(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.initiateOpenPosition(0, 0, 0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateOpenPosition(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.initiateClosePosition(emptyPosId, 0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateClosePosition(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.initiateWithdrawal(0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateWithdrawal(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateActionablePendingActions(EMPTY_PREVIOUS_DATA, 0);

        vm.expectRevert(pausedErr);
        protocol.refundSecurityDeposit(ADDR_ZERO);

        vm.expectRevert(pausedErr);
        protocol.transferPositionOwnership(emptyPosId, ADDR_ZERO);

        vm.expectRevert(pausedErr);
        protocol.liquidate("");
    }
}
