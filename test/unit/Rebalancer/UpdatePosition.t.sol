// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { RebalancerFixture } from "test/unit/Rebalancer/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The updatePosition function of the rebalancer contract
 * @custom:background Given a deployed rebalancer contract
 * @custom:and 2 users having deposited assets in the rebalancer
 */
contract TestRebalancerUpdatePosition is RebalancerFixture {
    /// @dev The address of this test contract
    address immutable USER_0;
    uint128 constant USER_0_DEPOSIT_AMOUNT = 2 ether;
    uint128 constant USER_1_DEPOSIT_AMOUNT = 3 ether;

    constructor() {
        USER_0 = address(this);
    }

    function setUp() public {
        super._setUp();

        wstETH.mintAndApprove(USER_0, 10_000 ether, address(rebalancer), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 10_000 ether, address(rebalancer), type(uint256).max);

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

        rebalancer.depositAssets(USER_0_DEPOSIT_AMOUNT, address(this));
        rebalancer.depositAssets(USER_1_DEPOSIT_AMOUNT, USER_1);
    }

    /**
     * @custom:scenario The position is updated for the first time (no previous version)
     * @custom:given A new position was created for the rebalancer for the first time
     * @custom:when The usdn protocol calls updatePosition with the new position ID
     * @custom:then The data is saved in the new position version
     * @custom:and The amount of pending assets is set back to 0
     * @custom:and The position version is incremented
     * @custom:and a PositionVersionUpdated event is emitted
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
            positionData.entryAccMultiplier,
            10 ** rebalancer.MULTIPLIER_DECIMALS(),
            "Entry multiplier accumulator should be 1"
        );
        assertEq(positionData.pnlMultiplier, 0, "PnL multiplier should be 0");
        assertEq(positionData.id.tick, newPosId.tick, "The tick of the position ID should be equal to newPosId.tick");
        assertEq(
            positionData.id.tickVersion,
            newPosId.tickVersion,
            "The tick version of the position ID should be equal to newPosId.tickVersion"
        );
        assertEq(
            positionData.id.index, newPosId.index, "The index of the position ID should be equal to newPosId.index"
        );

        // check the rebalancer state
        assertEq(rebalancer.getPendingAssetsAmount(), 0, "Pending assets amount should be 0");
        assertEq(
            rebalancer.getPositionVersion(),
            positionVersionBefore + 1,
            "The position version should have been incremented"
        );
    }
}
