// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { MockRebalancer } from "../utils/MockRebalancer.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IBaseRebalancer } from "../../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";

/// @custom:feature the _triggerRebalancer internal function of the UsdnProtocolLong contract
/// @custom:background a deployed USDN protocol initialized at equilibrium
contract TestUsdnProtocolLongTriggerRebalancer is UsdnProtocolBaseFixture {
    MockRebalancer mockedRebalancer;

    uint256 longBalance;
    uint256 vaultBalance;
    uint128 lastPrice;
    int256 remainingCollateral = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableRebalancer = true;
        super._setUp(params);
        longBalance = params.initialLong;
        vaultBalance = params.initialDeposit;
        lastPrice = params.initialPrice;

        mockedRebalancer = new MockRebalancer();

        vm.prank(ADMIN);
        protocol.setRebalancer(mockedRebalancer);
    }

    /**
     * @custom:scenario Trigger with an invalid trading expo
     * @custom:given An USDN protocol with a total expo below its long balance
     * @custom:when _triggerRebalancer is called
     * @custom:then The call reverts with an UsdnProtocolInvalidLongExpo error
     */
    function test_RevertWhen_triggerRebalancerWithTotalExpoBelowLongBalance() public {
        longBalance = protocol.getTotalExpo() + 1;

        vm.expectRevert(UsdnProtocolInvalidLongExpo.selector);
        protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);
    }

    /**
     * @custom:scenario Trigger with no rebalancer set
     * @custom:given The rebalancer being the zero address
     * @custom:when _triggerRebalancer is called
     * @custom:then nothing happens
     * @custom:and The long and vault balances should not change
     */
    function test_triggerRebalancerWithRebalancerNotSet() public {
        vm.prank(ADMIN);
        protocol.setRebalancer(IBaseRebalancer(address(0)));

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(newLongBalance, longBalance, "The long balance should not have changed");
        assertEq(newVaultBalance, vaultBalance, "The long balance should not have changed");
    }

    /**
     * @custom:scenario Trigger with not enough imbalance
     * @custom:given The USDN protocol's imbalance being below the threshold
     * @custom:when _triggerRebalancer is called
     * @custom:then The trigger should have been aborted
     * @custom:and The long and vault balances should not have changed
     */
    function test_triggerRebalancerWithNotEnoughImbalance() public {
        int256 imbalanceLimit = protocol.getCloseExpoImbalanceLimitBps();
        uint256 totalExpo = protocol.getTotalExpo();

        // calculate the long balance that would make the imbalance just below the trigger
        // -1 at the end just to compensate for precision errors during imbalance calculations
        longBalance = totalExpo
            - (vaultBalance * Constants.BPS_DIVISOR / uint256(imbalanceLimit - 1 + int256(Constants.BPS_DIVISOR))) - 1;

        // sanity check
        assertEq(
            imbalanceLimit - 1, protocol.i_calcImbalanceCloseBps(int256(vaultBalance), int256(longBalance), totalExpo)
        );

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(newLongBalance, longBalance, "The long balance should not have changed");
        assertEq(newVaultBalance, vaultBalance, "The long balance should not have changed");
    }

    /**
     * @custom:scenario The rebalancer is triggered but with no new position and 0 value in the previous position
     * @custom:given A rebalancer that was already triggered and has a position
     * @custom:when The rebalancer is triggered again
     * @custom:and There is no pending assets
     * @custom:and The value of the existing position is 10_000 wei
     * @custom:then The position value is gifted to the vault
     * @custom:and The position is closed
     * @custom:and no new position is opened
     */
    function test_triggerRebalancerWithNoPendingAssetsAndLowPosValue() public {
        uint8 assetDecimals = protocol.getAssetDecimals();
        uint128 amount = 10_000;

        // make sure there's enough imbalance
        vaultBalance *= 2;

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(mockedRebalancer),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: amount,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 2,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        mockedRebalancer.setCurrentStateData(0, protocol.getMaxLeverage(), posId);

        vm.prank(ADMIN);
        protocol.setMinLongPosition(10 ** assetDecimals);

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(
            newLongBalance,
            longBalance - amount + 1,
            "The value of the closed position should have been removed from the long balance"
        );
        assertEq(
            newVaultBalance,
            vaultBalance + amount - 1,
            "The value of the closed position should have been transferred to the vault"
        );
    }

    /**
     * @custom:scenario Trigger with a previous position with a liquidation price above the current price
     * @custom:given A rebalancer with an existing position
     * @custom:when The rebalancer is triggered with `lastPrice` above the position's liquidation price
     * @custom:then The trigger should be aborted
     * @custom:and The long and vault balances should not have changed
     */
    function test_triggerRebalancerWithExistingPositionThatShouldHaveBeenLiquidated() public {
        uint128 amount = 1 ether;

        // make sure there's enough imbalance
        vaultBalance *= 2;

        // assign a position to the rebalancer at a higher price
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(mockedRebalancer),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: amount,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice * 2,
                price: DEFAULT_PARAMS.initialPrice * 4
            })
        );

        mockedRebalancer.setCurrentStateData(0, protocol.getMaxLeverage(), posId);

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(DEFAULT_PARAMS.initialPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(newLongBalance, longBalance, "The long balance should not have changed");
        assertEq(newVaultBalance, vaultBalance, "The vault balance should not have changed");
    }

    /**
     * @custom:scenario The rebalancer is triggered with no existing position
     * @custom:given A rebalancer with no position for the current version
     * @custom:and enough remaining collateral to trigger a bonus
     * @custom:when The rebalancer is triggered
     * @custom:then A new position is opened
     * @custom:and The new long balance should equal the previous one + pending assets + bonus
     * @custom:and The new vault balance should equal the previous one - bonus
     */
    function test_triggerRebalancerWithNoPreviousPosition() public {
        uint128 bonus = uint128(uint256(remainingCollateral) * protocol.getRebalancerBonusBps() / Constants.BPS_DIVISOR);

        // decrease the trading expo so there's some to fill
        longBalance = vaultBalance * 2;

        uint128 pendingAssets = 1 ether;
        vm.prank(address(mockedRebalancer));
        wstETH.mintAndApprove(address(mockedRebalancer), pendingAssets, address(protocol), type(uint256).max);

        mockedRebalancer.setCurrentStateData(
            pendingAssets, protocol.getMaxLeverage(), PositionId(Constants.NO_POSITION_TICK, 0, 0)
        );

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(
            newLongBalance,
            longBalance + pendingAssets + bonus,
            "The value of the opened position + bonus should have been added to the long balance"
        );
        assertEq(
            newVaultBalance, vaultBalance - bonus, "The bonus should have been subtracted from the vault's balance"
        );
    }

    /**
     * @custom:scenario The rebalancer is triggered with no existing position
     * @custom:given A rebalancer with an existing position
     * @custom:and Enough remaining collateral to trigger a bonus
     * @custom:when The rebalancer is triggered
     * @custom:then The previous position is closed
     * @custom:and A new position is opened
     * @custom:and The new long balance should equal the previous one + pending assets + bonus
     * @custom:and The new vault balance should equal the previous one - bonus
     */
    function test_triggerRebalancer() public {
        uint128 bonus = uint128(uint256(remainingCollateral) * protocol.getRebalancerBonusBps() / Constants.BPS_DIVISOR);
        uint128 amount = 1 ether;

        // decrease the trading expo so there's some to fill
        longBalance = vaultBalance * 2;

        // assign a position to the rebalancer at a higher price
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(mockedRebalancer),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: amount,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 3,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        uint128 pendingAssets = 1 ether;
        vm.prank(address(mockedRebalancer));
        wstETH.mintAndApprove(address(mockedRebalancer), pendingAssets, address(protocol), type(uint256).max);

        mockedRebalancer.setCurrentStateData(pendingAssets, protocol.getMaxLeverage(), posId);

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(
            newLongBalance,
            longBalance + pendingAssets + bonus,
            "The value of the opened position + bonus should have been added to the long balance"
        );
        assertEq(
            newVaultBalance, vaultBalance - bonus, "The bonus should have been subtracted from the vault's balance"
        );
    }

    /**
     * @custom:scenario Trigger with an empty rebalancer
     * @custom:given The rebalancer with no deposit
     * @custom:when The rebalancer is triggered
     * @custom:then The rebalancer position version should not be incremented
     */
    function test_triggerEmptyRebalancer() public {
        uint256 totalExpo = protocol.getTotalExpo();
        protocol.i_triggerRebalancer(lastPrice, totalExpo - 1, totalExpo * 10, 0);
        assertEq(rebalancer.getPositionVersion(), 0, "Version should not be incremented");
    }
}
