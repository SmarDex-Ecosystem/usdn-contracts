// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

/// @custom:feature The pausable functions of the `usdnProtocol`
contract TestUsdnProtocolPausable is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);
    }

    /**
     * @custom:scenario Call all functions with the `whenNotPaused` modifier
     * @custom:given A paused usdnProtocol
     * @custom:when Each function is called
     * @custom:then Each function should revert with the `EnforcedPause` error
     */
    function test_RevertWhen_callsPausedFunctions() public {
        bytes4 pausedErr = PausableUpgradeable.EnforcedPause.selector;
        address payable ADDR_ZERO = payable(address(0));
        PositionId memory emptyPosId = PositionId(0, 0, 0);

        vm.prank(ADMIN);
        protocol.pause();
        assertTrue(protocol.isPaused(), "The protocol should be paused");

        vm.expectRevert(pausedErr);
        protocol.initiateDeposit(0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateDeposit(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.initiateOpenPosition(0, 0, 0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.validateOpenPosition(ADDR_ZERO, "", EMPTY_PREVIOUS_DATA);

        vm.expectRevert(pausedErr);
        protocol.initiateClosePosition(emptyPosId, 0, 0, ADDR_ZERO, ADDR_ZERO, 0, "", EMPTY_PREVIOUS_DATA, "");

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
        protocol.transferPositionOwnership(emptyPosId, "", ADDR_ZERO);

        vm.expectRevert(pausedErr);
        protocol.liquidate("");
    }

    /**
     * @custom:scenario Ensure that no funding is possible during the pause period
     * @custom:given A active usdnProtocol with funding enabled
     * @custom:when {pause} is called
     * @custom:and 10 days have passed
     * @custom:and {unpause} is called
     * @custom:then No funding should be possible during the pause period
     */
    function test_NoFundingDuringPausePeriod() public {
        uint256 balanceVaultBefore = protocol.getBalanceVault();
        uint256 balanceLongBefore = protocol.getBalanceLong();
        uint256 snapshotId = vm.snapshotState();

        vm.prank(ADMIN);
        protocol.pause();
        skip(10 days);
        vm.prank(ADMIN);
        protocol.unpause();
        protocol.liquidate(abi.encode(params.initialPrice));
        uint256 balanceLong = protocol.getBalanceLong();
        uint256 balanceVault = protocol.getBalanceVault();
        assertEq(balanceVaultBefore, balanceVault, "The vault balance should not change");
        assertEq(balanceLongBefore, balanceLong, "The long balance should not change");

        vm.revertToState(snapshotId);
        skip(10 days);
        protocol.liquidate(abi.encode(params.initialPrice));
        assertTrue(protocol.getBalanceLong() != balanceLong, "The long balance should be different");
        assertTrue(protocol.getBalanceVault() != balanceVault, "The vault balance should be different");
    }

    /**
     * @custom:scenario Ensure that the funding will continue during the pause period if the safe versions are called
     * @custom:given A active usdnProtocol with funding enabled
     * @custom:when {pause} is called
     * @custom:and 10 days have passed
     * @custom:and {unpause} is called
     * @custom:then Funding should occur
     */
    function test_fundingSafeVersion() public {
        uint256 balanceVaultBefore = protocol.getBalanceVault();
        uint256 balanceLongBefore = protocol.getBalanceLong();

        vm.prank(ADMIN);
        protocol.pauseSafe();
        skip(10 days);
        vm.prank(ADMIN);
        protocol.unpauseSafe();
        protocol.liquidate(abi.encode(params.initialPrice));
        uint256 balanceLong = protocol.getBalanceLong();
        uint256 balanceVault = protocol.getBalanceVault();
        assertTrue(balanceVaultBefore != balanceVault, "The vault balance should be different");
        assertTrue(balanceLongBefore != balanceLong, "The long balance should be different");
    }
}
