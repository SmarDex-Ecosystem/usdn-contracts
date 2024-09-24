// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

/// @custom:feature The pausable functions of the `usdnProtocol`
contract TestUsdnProtocolPausable is UsdnProtocolBaseFixture {
    PositionId internal emptyPosId = PositionId(0, 0, 0);
    address payable internal constant ADDR_ZERO = payable(address(0));

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        _pauseProtocol(ADMIN);
    }

    /**
     * @custom:scenario The user initiates a deposit action with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {initiateDeposit}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_initiateDepositPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.initiateDeposit(0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user validates a deposit action with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {validateDeposit}
     * @custom:then The protocol reverts with a `EnforcedPause`
     */
    function test_RevertWhen_validateDepositPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateDeposit(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates an open position with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {initiateOpenPosition}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_initiateOpenPositionPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.initiateOpenPosition(0, 0, 0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user validates an open position with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {validateOpenPosition}
     * @custom:then The protocol reverts with a `EnforcedPause`
     */
    function test_RevertWhen_validateOpenPositionPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateOpenPosition(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates a close position with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {initiateClosePosition}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_initiateClosePositionPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.initiateClosePosition(emptyPosId, 0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user validate a close position with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {validateClosePosition}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_validateClosePositionPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateClosePosition(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates a withdrawal action with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {initiateWithdrawal}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_initiateWithdrawalPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.initiateWithdrawal(0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user validates a withdrawal action with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {validateWithdrawal}
     * @custom:then The protocol reverts with a `EnforcedPause`
     */
    function test_RevertWhen_validateWithdrawalPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateWithdrawal(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user validates pending actions with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {validateActionablePendingActions}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_validateActionablePendingActionsPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateActionablePendingActions(EMPTY_PREVIOUS_DATA, 0);
    }

    /**
     * @custom:scenario The user requests the security deposit refund with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {refundSecurityDeposit}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_refundSecurityDepositPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.refundSecurityDeposit(ADDR_ZERO);
    }

    /**
     * @custom:scenario The user transfers a user position ownership with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {transferPositionOwnership}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_transferOwnershipPaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.transferPositionOwnership(emptyPosId, ADDR_ZERO);
    }

    /**
     * @custom:scenario The user liquidates with a paused protocol
     * @custom:given A paused protocol
     * @custom:when The user calls {liquidate}
     * @custom:then The call reverts with `EnforcedPause`
     */
    function test_RevertWhen_liquidatePaused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.liquidate("");
    }
}
