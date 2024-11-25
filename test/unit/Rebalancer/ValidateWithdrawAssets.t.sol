// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { USER_1 } from "../../utils/Constants.sol";
import { RebalancerFixture } from "./utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The `validateWithdrawAssets` function of the rebalancer contract
 * @custom:background Given a user has made a deposit and initiated a withdrawal of their unincluded assets
 */
contract TestRebalancerValidateWithdrawAssets is RebalancerFixture {
    uint88 constant INITIAL_DEPOSIT = 3 ether;

    UserDeposit initialUserDeposit;
    uint128 initialPendingAssets;
    uint88 minAssetDeposit;

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(address(this), 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 10_000 ether, address(rebalancer), type(uint256).max);

        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, address(this));
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        rebalancer.initiateWithdrawAssets();

        initialUserDeposit = rebalancer.getUserDepositData(address(this));
        initialPendingAssets = rebalancer.getPendingAssetsAmount();
        minAssetDeposit = uint88(rebalancer.getMinAssetDeposit());
    }

    function test_setUp() public view {
        assertGe(INITIAL_DEPOSIT, rebalancer.getMinAssetDeposit());
    }

    /**
     * @custom:scenario The user validates a withdrawal of their full deposit to their address
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal of their full deposit to their address
     * @custom:then The deposit data is erased
     * @custom:and The pending assets amount is updated
     * @custom:and The user receives the assets
     * @custom:and The {AssetsWithdrawn} event is emitted
     */
    function test_validateWithdrawalFull() public {
        _validateWithdrawalScenario(address(this), INITIAL_DEPOSIT);
    }

    /**
     * @custom:scenario The user validates a withdrawal of part of their deposit to their address
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal of part of the deposit to their address
     * @custom:then The deposit amount is updated
     * @custom:and The deposit initiate timestamp is set to zero
     * @custom:and The pending assets amount is updated
     * @custom:and The user receives the assets
     * @custom:and The {AssetsWithdrawn} event is emitted
     */
    function test_validateWithdrawalPartial() public {
        _validateWithdrawalScenario(address(this), INITIAL_DEPOSIT - minAssetDeposit);
    }

    /**
     * @custom:scenario The user validates a withdrawal of their full deposit to another address
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal of their full deposit to another address
     * @custom:then The deposit data is erased
     * @custom:and The pending assets amount is updated
     * @custom:and The other address receives the assets
     * @custom:and The {AssetsWithdrawn} event is emitted
     */
    function test_validateWithdrawalFullTo() public {
        _validateWithdrawalScenario(USER_1, INITIAL_DEPOSIT);
    }

    /**
     * @custom:scenario The user validates a withdrawal of part of their deposit to another address
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal of part of the deposit to another address
     * @custom:then The deposit amount is updated
     * @custom:and The deposit initiate timestamp is set to zero
     * @custom:and The pending assets amount is updated
     * @custom:and The other address receives the assets
     * @custom:and The {AssetsWithdrawn} event is emitted
     */
    function test_validateWithdrawalPartialTo() public {
        _validateWithdrawalScenario(USER_1, INITIAL_DEPOSIT - minAssetDeposit);
    }

    /**
     * @dev Helper function to test the withdrawal validation
     * @param to The address to which the assets are withdrawn
     * @param amount The amount of assets to withdraw
     */
    function _validateWithdrawalScenario(address to, uint88 amount) internal {
        skip(rebalancer.getTimeLimits().validationDelay);

        uint256 balanceBefore = wstETH.balanceOf(to);

        vm.expectEmit();
        emit AssetsWithdrawn(address(this), to, amount);
        rebalancer.validateWithdrawAssets(amount, to);

        UserDeposit memory userDeposit = rebalancer.getUserDepositData(address(this));
        assertEq(userDeposit.initiateTimestamp, 0, "initiate timestamp");
        if (amount == INITIAL_DEPOSIT) {
            assertEq(userDeposit.entryPositionVersion, 0, "full withdrawal: entry position version");
            assertEq(userDeposit.amount, 0, "full withdrawal: deposit amount");
        } else {
            assertEq(
                userDeposit.entryPositionVersion,
                initialUserDeposit.entryPositionVersion,
                "partial withdrawal: entry position version"
            );
            assertEq(userDeposit.amount, INITIAL_DEPOSIT - amount, "partial withdrawal: deposit amount");
        }

        assertEq(rebalancer.getPendingAssetsAmount(), initialPendingAssets - amount, "pending assets amount");
        assertEq(wstETH.balanceOf(to), balanceBefore + amount, "user balance");
    }

    /**
     * @custom:scenario The user validates a withdrawal to the zero address
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal to the zero address
     * @custom:then The call reverts with a {RebalancerInvalidAddressTo} error
     */
    function test_RevertWhen_validateWithdrawalToZeroAddress() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        vm.expectRevert(RebalancerInvalidAddressTo.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(0));
    }

    /**
     * @custom:scenario The user validates a withdrawal with zero amount
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal with zero amount
     * @custom:then The call reverts with a {RebalancerInvalidAmount} error
     */
    function test_RevertWhen_validateWithdrawalWithZeroAmount() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        vm.expectRevert(RebalancerInvalidAmount.selector);
        rebalancer.validateWithdrawAssets(0, address(this));
    }

    /**
     * @custom:scenario The user validates a withdrawal with an amount greater than the deposit
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal with an amount greater than the deposit
     * @custom:then The call reverts with a {RebalancerInvalidAmount} error
     */
    function test_RevertWhen_validateWithdrawalWithExcessAmount() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        vm.expectRevert(RebalancerInvalidAmount.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT + 1, address(this));
    }

    /**
     * @custom:scenario The user validates a withdrawal with an amount that would leave an insufficient remaining amount
     * @custom:given The user waits until the validation delay has passed
     * @custom:when The user validates the withdrawal with an amount that would leave an insufficient remaining amount
     * @custom:then The call reverts with a {RebalancerInsufficientAmount} error
     */
    function test_RevertWhen_validateWithdrawalWithInsufficientRemainingAmount() public {
        skip(rebalancer.getTimeLimits().validationDelay);
        uint88 withdrawAmount = INITIAL_DEPOSIT - minAssetDeposit + 1;
        vm.expectRevert(RebalancerInsufficientAmount.selector);
        rebalancer.validateWithdrawAssets(withdrawAmount, address(this));
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal too soon
     * @custom:when The user tries to validate the withdrawal before the validation delay
     * @custom:then The call reverts with a {RebalancerValidateTooEarly} error
     */
    function test_RevertWhen_validateWithdrawalBeforeDelay() public {
        vm.expectRevert(RebalancerValidateTooEarly.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal too late
     * @custom:given The validation deadline has passed
     * @custom:or The action cooldown has passed
     * @custom:when The user tries to validate the withdrawal
     * @custom:then The call reverts with a {RebalancerActionCooldown} error
     */
    function test_RevertWhen_validateWithdrawalAfterDeadline() public {
        skip(rebalancer.getTimeLimits().validationDeadline + 1);
        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));

        skip(rebalancer.getTimeLimits().actionCooldown);
        vm.expectRevert(RebalancerActionCooldown.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal that has not been initiated
     * @custom:given The user has initiated and validated a deposit, but not initiated a withdrawal
     * @custom:when The user tries to validate a withdrawal that has not been initiated
     * @custom:then The call reverts with a {RebalancerNoPendingAction} error
     */
    function test_RevertWhen_validateWithdrawalNotInitiated() public {
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, USER_1);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();

        vm.expectRevert(RebalancerNoPendingAction.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, USER_1);
        vm.stopPrank();
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal but they don't have any funds in the rebalancer
     * @custom:given The user has no active or liquidated position or unincluded assets in the rebalancer
     * @custom:when The user tries to validate a withdrawal
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_validateWithdrawalNotInRebalancer() public {
        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        vm.prank(USER_1);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, USER_1);
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal but they have not validated their deposit
     * @custom:given The user has initiated a deposit but hasn't validated it yet
     * @custom:when The user tries to validate a withdrawal immediately after the deposit
     * @custom:or The user tries to validate a withdrawal after the validation delay
     * @custom:or The user tries to validate a withdrawal after the action cooldown
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_validateWithdrawalDepositNotValidated() public {
        vm.startPrank(USER_1);
        rebalancer.initiateDepositAssets(INITIAL_DEPOSIT, USER_1);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, USER_1);

        skip(rebalancer.getTimeLimits().validationDelay);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, USER_1);

        skip(rebalancer.getTimeLimits().actionCooldown);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, USER_1);
        vm.stopPrank();
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal but the assets are already used in a position
     * @custom:given The user's deposit was included in the protocol
     * @custom:when The user tries to validate a withdrawal
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_validateWithdrawalIncludedInProtocol() public {
        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal but the assets were already in a liquidated position
     * @custom:given The user's deposit was in a position that got liquidated
     * @custom:when The user tries to validate a withdrawal and the position was liquidated with a new position being
     * created
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_validateWithdrawalLiquidatedWithNewPosition() public {
        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 0);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The user tries to validate a withdrawal but the assets were already in a liquidated position
     * @custom:given The user's deposit was in a position that got liquidated
     * @custom:when The user tries to validate a withdrawal and the position was liquidated
     * @custom:then The call reverts with {RebalancerWithdrawalUnauthorized}
     */
    function test_RevertWhen_validateWithdrawalLiquidatedWithNoNewPosition() public {
        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(Types.PositionId(0, 0, 0), 1);

        vm.expectRevert(RebalancerWithdrawalUnauthorized.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));
    }

    /**
     * @custom:scenario The token tries to re-enter the rebalancer during a validate withdrawal
     * @custom:when The token tries to re-enter the rebalancer during a withdrawal
     * @custom:then The call reverts with a {ReentrancyGuardReentrantCall} error
     */
    function test_RevertWhen_withdrawalWithReentrancy() public {
        wstETH.setReentrant(true);
        skip(rebalancer.getTimeLimits().validationDelay);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        rebalancer.validateWithdrawAssets(INITIAL_DEPOSIT, address(this));
    }
}
