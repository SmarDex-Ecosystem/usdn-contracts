// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { DEPLOYER } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { ProtocolAction } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test the _sendRewardsToLiquidator internal function of the actions utils library
 * @custom:given A protocol with increased rewards and gas price
 */
contract TestUsdnProtocolActionsSendRewardsToLiquidator is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 1 ether;
        _setUp(params);

        // Change The rewards calculations parameters to not be dependent of the initial values
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(500_000, 1_000_000, 200_000, 200_000, 8000 gwei, 20_000);
        // Puts the gas at 8000 gwei
        vm.txGasPrice(8000 gwei);
    }

    function test_sendRewardsToLiquidatorLowerThan() public {
        uint256 rewards =
            liquidationRewardsManager.getLiquidationRewards(1, 0, false, false, ProtocolAction.None, "", "");

        protocol.i_sendRewardsToLiquidator(1, 0, false, false, ProtocolAction.None, "", "");

        assertEq(wstETH.balanceOf(address(this)), rewards, "Balance increase by the rewards");
    }

    function test_sendRewardsToLiquidatorHigherThan() public {
        vm.startPrank(DEPLOYER);
        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint128(usdn.sharesOf(DEPLOYER)),
            DEPLOYER,
            payable(DEPLOYER),
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateWithdrawal(payable(DEPLOYER), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        uint256 balanceVault = protocol.getBalanceVault();

        protocol.i_sendRewardsToLiquidator(3, 0, true, true, ProtocolAction.None, "", "");

        assertEq(wstETH.balanceOf(address(this)), balanceVault, "Balance increase by the vault balance");
    }

    receive() external payable { }
}
