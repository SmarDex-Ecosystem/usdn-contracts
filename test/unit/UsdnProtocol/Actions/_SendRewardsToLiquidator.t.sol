// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DEPLOYER } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the _sendRewardsToLiquidator internal function of the actions utils library
 * @custom:given A protocol with increased rewards and gas price
 */
contract TestUsdnProtocolActionsSendRewardsToLiquidator is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        // increase the rewards
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(500_000, 1_000_000, 200_000, 200_000, 8000 gwei, 20_000);
        // puts the gas at 8000 gwei
        vm.txGasPrice(8000 gwei);
    }

    /**
     * @custom:scenario The protocol sends rewards to the user
     * @custom:given The rewards are lower than the vault balance
     * @custom:when The protocol sends the rewards to the liquidator
     * @custom:then The user receives the rewards calculated by the liquidation rewards manager
     */
    function test_sendRewardsToLiquidatorLowerThan() public {
        LiqTickInfo[] memory liquidatedTicks = new LiqTickInfo[](1);
        liquidatedTicks[0] = LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1020 ether,
            priceWithoutPenalty: 1000 ether
        });
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, false, RebalancerAction.None, ProtocolAction.None, "", ""
        );

        vm.expectEmit();
        emit LiquidatorRewarded(address(this), rewards);
        protocol.i_sendRewardsToLiquidator(liquidatedTicks, false, RebalancerAction.None, ProtocolAction.None, "", "");

        assertEq(wstETH.balanceOf(address(this)), rewards, "Balance increase by the rewards");
    }

    /**
     * @custom:scenario The protocol sends the entire vault balance to the user
     * @custom:given The rewards are higher than the vault balance
     * @custom:when The protocol sends the rewards to the liquidator
     * @custom:then The user receives the entire vault balance
     */
    function test_sendRewardsToLiquidatorHigherThan() public {
        vm.startPrank(DEPLOYER);
        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint152(usdn.sharesOf(DEPLOYER)),
            DEPLOYER,
            payable(DEPLOYER),
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateWithdrawal(payable(DEPLOYER), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        uint256 balanceVault = protocol.getBalanceVault();

        LiqTickInfo[] memory liquidatedTicks = new LiqTickInfo[](3);
        liquidatedTicks[0] = LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1020 ether,
            priceWithoutPenalty: 1000 ether
        });
        liquidatedTicks[1] = LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1010 ether,
            priceWithoutPenalty: 990 ether
        });
        liquidatedTicks[2] = LiqTickInfo({
            totalPositions: 1,
            totalExpo: 10 ether,
            remainingCollateral: 0.2 ether,
            tickPrice: 1000 ether,
            priceWithoutPenalty: 980 ether
        });

        vm.expectEmit();
        emit LiquidatorRewarded(address(this), balanceVault);
        protocol.i_sendRewardsToLiquidator(
            liquidatedTicks, true, RebalancerAction.ClosedOpened, ProtocolAction.None, "", ""
        );

        assertEq(wstETH.balanceOf(address(this)), balanceVault, "Balance increase by the vault balance");
    }

    receive() external payable { }
}
