// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { ForkUniversalRouterBaseIntegrationFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";
import { IStETH } from "test/integration/UniversalRouter/interfaces/IStETH.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

/**
 * @custom:feature Test commands wrap and unwrap stETH
 * @custom:background A initiated universal router
 */
contract TestForkUniversalRouterExecuteStETH is ForkUniversalRouterBaseIntegrationFixture {
    uint256 constant BASE_AMOUNT = 1000 ether;
    IStETH stETH;

    /// @notice The error message for insufficient token
    error InsufficientToken();

    function setUp() external {
        _setUp();

        deal(address(wstETH), address(this), BASE_AMOUNT);
        stETH = IStETH(address(router.STETH()));
    }

    /**
     * @custom:scenario Test the `WRAP_STETH` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `stETH`
     * @custom:when The `execute` function is called for `WRAP_STETH` command
     * @custom:then The `WRAP_STETH` command should be executed
     * @custom:and The `wsteth` user balance should be increased
     */
    function test_executeWrapStETH() external {
        // unwrap
        wstETH.unwrap(BASE_AMOUNT);
        stETH.transfer(address(router), stETH.balanceOf(address(this)));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.WRAP_STETH) << (256 - 8)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, Constants.CONTRACT_BALANCE);
        uint256 balanceWstETHBefore = wstETH.balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(wstETH.balanceOf(address(this)), balanceWstETHBefore, "wrong wstETH balance");
    }

    /**
     * @custom:scenario Test the `UNWRAP_WSTETH` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `wstETH`
     * @custom:when The `execute` function is called for `UNWRAP_WSTETH` command
     * @custom:then The `UNWRAP_WSTETH` command should be executed
     * @custom:and The `stETH` user balance should be increased
     */
    function test_executeUnwrapStETH() external {
        // transfer
        wstETH.transfer(address(router), BASE_AMOUNT);
        uint256 balanceStETHBefore = stETH.balanceOf(address(this));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.UNWRAP_WSTETH) << (256 - 8)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, stETH.getPooledEthByShares(BASE_AMOUNT));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(stETH.balanceOf(address(this)), balanceStETHBefore, "wrong stETH balance");
        assertEq(wstETH.balanceOf(address(router)), 0, "wrong wstETH balance");
    }

    /**
     * @custom:scenario Test the `UNWRAP_WSTETH` command when the user has not enough balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with one `wstETH`
     * @custom:when The `execute` function is called for `UNWRAP_WSTETH` command
     * @custom:then The `UNWRAP_WSTETH` command should revert
     */
    function test_RevertWhen_executeUnwrapStETHEnoughBalance() external {
        // transfer
        wstETH.transfer(address(router), 1);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.UNWRAP_WSTETH) << (256 - 8)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, stETH.getPooledEthByShares(wstETH.balanceOf(address(router))) + 1);

        // execution
        vm.expectRevert(InsufficientToken.selector);
        router.execute(commands, inputs);
    }
}
