// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RebalancerFixture } from "./utils/Fixtures.sol";
import { USER_1, USER_2 } from "../../utils/Constants.sol";

import { PositionId } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The updatePosition function of the rebalancer contract
 * @custom:background Given a deployed rebalancer contract
 * @custom:and 2 users having deposited assets in the rebalancer
 */
contract TestRebalancerUpdatePosition is RebalancerFixture {
    /// @dev The address of this test contract
    address immutable USER_0;
    uint88 constant USER_0_DEPOSIT_AMOUNT = 2 ether;
    uint88 constant USER_1_DEPOSIT_AMOUNT = 3 ether;

    constructor() {
        USER_0 = address(this);
    }

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(USER_0, 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_2, 10_000 ether, address(rebalancer), type(uint256).max);

        // Sanity checks
        assertGe(
            USER_0_DEPOSIT_AMOUNT,
            rebalancer.getMinAssetDeposit(),
            "Amount deposited for address(this) lower than rebalancer min amount"
        );
        assertGe(
            USER_1_DEPOSIT_AMOUNT,
            rebalancer.getMinAssetDeposit(),
            "Amount deposited for USER_1 lower than rebalancer min amount"
        );

        rebalancer.initiateDepositAssets(USER_0_DEPOSIT_AMOUNT, address(this));
        rebalancer.initiateDepositAssets(USER_1_DEPOSIT_AMOUNT, USER_1);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.prank(USER_1);
        rebalancer.validateDepositAssets();
    }

    /**
     * @custom:scenario An address that is not the USDN protocol calls {updatePosition}
     * @custom:given The caller not being the USDN protocol
     * @custom:when {updatePosition} is called
     * @custom:then The call reverts with a {RebalancerUnauthorized} error
     */
    function test_RevertWhen_callerIsNotTheProtocol() external {
        vm.expectRevert(RebalancerUnauthorized.selector);
        rebalancer.updatePosition(PositionId(0, 0, 0), 0);
    }

    /**
     * @custom:scenario The position is updated for the first time (no previous version)
     * @custom:given A new position was created for the rebalancer for the first time
     * @custom:when The usdn protocol calls {updatePosition} with the new position ID
     * @custom:then The data is saved in the new position version
     * @custom:and The amount of pending assets is set back to 0
     * @custom:and The position version is incremented
     * @custom:and A {PositionVersionUpdated} event is emitted
     */
    function test_updatePositionForTheFirstTime() external {
        PositionId memory newPosId = PositionId({ tick: 200, tickVersion: 1, index: 3 });
        uint128 pendingAssetsBefore = rebalancer.getPendingAssetsAmount();
        uint128 positionVersionBefore = rebalancer.getPositionVersion();

        vm.prank(address(usdnProtocol));
        vm.expectEmit();
        emit PositionVersionUpdated(positionVersionBefore + 1);
        rebalancer.updatePosition(newPosId, 0);

        // check the position data
        PositionData memory positionData = rebalancer.getPositionData(rebalancer.getPositionVersion());
        assertEq(positionData.amount, pendingAssetsBefore);
        assertEq(
            positionData.entryAccMultiplier, rebalancer.MULTIPLIER_FACTOR(), "Entry multiplier accumulator should be 1x"
        );
        assertEq(
            positionData.id.tick, newPosId.tick, "The tick of the position ID should be equal to the provided value"
        );
        assertEq(
            positionData.id.tickVersion,
            newPosId.tickVersion,
            "The tick version of the position ID should be equal to the provided value"
        );
        assertEq(
            positionData.id.index, newPosId.index, "The index of the position ID should be equal to the provided value"
        );

        // check the rebalancer state
        assertEq(rebalancer.getPendingAssetsAmount(), 0, "Pending assets amount should be 0");
        assertEq(
            rebalancer.getPositionVersion(),
            positionVersionBefore + 1,
            "The position version should have been incremented"
        );
    }

    /**
     * @custom:scenario The position is updated 2 times
     * @custom:given A new position was created for the rebalancer twice
     * @custom:and Another user deposited assets between the updates
     * @custom:when The usdn protocol calls {updatePosition} with the new position ID
     * @custom:then The data is saved in the new position version
     * @custom:and The amount of pending assets is set back to 0
     * @custom:and The position version is incremented
     * @custom:and A {PositionVersionUpdated} event is emitted
     */
    function test_updatePositionWithAnExistingPosition() external {
        PositionId memory posId1 = PositionId({ tick: 200, tickVersion: 1, index: 3 });
        PositionId memory posId2 = PositionId({ tick: 400, tickVersion: 8, index: 27 });
        uint128 positionVersionBefore = rebalancer.getPositionVersion();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(posId1, 0);

        uint88 user2DepositedAmount = 5 ether;
        vm.startPrank(USER_2);
        rebalancer.initiateDepositAssets(user2DepositedAmount, USER_2);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.stopPrank();

        // simulate a profit of 10% when closing the position
        uint128 posVersion2Value = (USER_0_DEPOSIT_AMOUNT + USER_1_DEPOSIT_AMOUNT) * 11 / 10;
        vm.expectEmit();
        emit PositionVersionUpdated(positionVersionBefore + 2);
        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(posId2, posVersion2Value);

        assertEq(
            rebalancer.getPositionVersion(),
            positionVersionBefore + 2,
            "The position version should have been incremented twice"
        );

        // check the position data of the second version
        PositionData memory positionData = rebalancer.getPositionData(rebalancer.getPositionVersion());
        assertEq(positionData.amount, posVersion2Value + user2DepositedAmount);
        assertEq(
            positionData.entryAccMultiplier,
            rebalancer.MULTIPLIER_FACTOR() + rebalancer.MULTIPLIER_FACTOR() / 10,
            "Entry multiplier accumulator of the position should be 1.1x"
        );
        assertEq(positionData.id.tick, posId2.tick, "Tick mismatch");
        assertEq(positionData.id.tickVersion, posId2.tickVersion, "Tick version mismatch");
        assertEq(positionData.id.index, posId2.index, "Index mismatch");
    }

    /**
     * @custom:scenario The position is updated after the previous version got liquidated
     * @custom:given A new position was created for the rebalancer for the first time
     * @custom:and It got liquidated
     * @custom:and A user deposited some assets
     * @custom:when The usdn protocol calls {updatePosition} with the new position ID
     * @custom:and The value of the previous version being 0
     * @custom:then The data is saved in the new position version
     * @custom:and The last liquidated version is set to the previous version
     */
    function test_updatePositionWithALiquidatedPosition() external {
        PositionId memory posId1 = PositionId({ tick: 200, tickVersion: 1, index: 3 });
        PositionId memory posId2 = PositionId({ tick: 400, tickVersion: 8, index: 27 });
        uint128 positionVersionBefore = rebalancer.getPositionVersion();

        vm.prank(address(usdnProtocol));
        rebalancer.updatePosition(posId1, 0);

        // add some pending assets before updating again
        uint88 user2DepositedAmount = 5 ether;
        vm.startPrank(USER_2);
        rebalancer.initiateDepositAssets(user2DepositedAmount, USER_2);
        skip(rebalancer.getTimeLimits().validationDelay);
        rebalancer.validateDepositAssets();
        vm.stopPrank();

        vm.expectEmit();
        emit PositionVersionUpdated(positionVersionBefore + 2);
        vm.prank(address(usdnProtocol));
        // 0 as a value here means there was no collateral left in the closed position
        rebalancer.updatePosition(posId2, 0);

        assertEq(
            rebalancer.getLastLiquidatedVersion(),
            positionVersionBefore + 1,
            "The last liquidated version should be the version that was supposed to be closed"
        );

        // check the second position's data
        PositionData memory positionData = rebalancer.getPositionData(rebalancer.getPositionVersion());
        assertEq(positionData.amount, user2DepositedAmount, "Only the funds of USER_2 should be in the position");
        assertEq(
            positionData.entryAccMultiplier, rebalancer.MULTIPLIER_FACTOR(), "Entry multiplier accumulator should be 1x"
        );
    }
}
