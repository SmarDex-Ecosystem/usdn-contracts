// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DEPLOYER } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
        uint256 rewards = liquidationRewardsManager.getLiquidationRewards(
            1, 0, false, Types.RebalancerAction.None, ProtocolAction.None, "", ""
        );

        vm.expectEmit();
        emit LiquidatorRewarded(address(this), rewards);
        protocol.i_sendRewardsToLiquidator(1, 0, false, Types.RebalancerAction.None, ProtocolAction.None, "", "");

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
            DISABLE_AMOUNT_OUT_MIN,
            DEPLOYER,
            payable(DEPLOYER),
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateWithdrawal(payable(DEPLOYER), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        uint256 balanceVault = protocol.getBalanceVault();

        vm.expectEmit();
        emit LiquidatorRewarded(address(this), balanceVault);
        protocol.i_sendRewardsToLiquidator(3, 0, true, Types.RebalancerAction.ClosedOpened, ProtocolAction.None, "", "");

        assertEq(wstETH.balanceOf(address(this)), balanceVault, "Balance increase by the vault balance");
    }

    receive() external payable { }
}
