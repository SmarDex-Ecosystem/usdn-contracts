// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { ForkUniversalRouterBaseIntegrationFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { IStETH } from "src/UniversalRouter/interfaces/ISTETH.sol";

/**
 * @custom:feature Test commands lower than fourth boundary of the `execute` function
 * @custom:background A initiated universal router
 */
contract ForkTestExecuteFourthBoundary is ForkUniversalRouterBaseIntegrationFixture {
    uint256 constant BASE_AMOUNT = 1 ether;
    IStETH stETH;

    function setUp() external {
        _setUp();

        deal(address(wstETH), address(this), BASE_AMOUNT * 1e3);
        stETH = IStETH(router.STETH());
    }

    /**
     * @custom:scenario Test the `WRAP_STETH` command using the router balance
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some `stETH`
     * @custom:when The `execute` function is called for `WRAP_STETH` command
     * @custom:then The `WRAP_STETH` command should be executed
     * @custom:and The `wsteth` user balance should be increased
     */
    function test_execute_wrap_steth() external {
        // unwrap
        uint256 wstETHBalance = wstETH.balanceOf(address(this));
        wstETH.unwrap(wstETHBalance);
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
        assertGt(wstETH.balanceOf(address(this)), balanceWstETHBefore, "wrong wsteth balance");
    }

    /**
     * @custom:scenario Test the `UNWRAP_WSTETH` command using the router balance
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some `stETH`
     * @custom:when The `execute` function is called for `UNWRAP_WSTETH` command
     * @custom:then The `UNWRAP_WSTETH` command should be executed
     * @custom:and The `stETH` user balance should be increased
     */
    function test_execute_unwrap_steth() external {
        // transfer
        uint256 wstETHBalance = wstETH.balanceOf(address(this));
        wstETH.transfer(address(router), wstETHBalance);
        uint256 balanceStETHBefore = stETH.balanceOf(address(this));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.UNWRAP_WSTETH) << (256 - 8)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, stETH.getPooledEthByShares(wstETHBalance));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(stETH.balanceOf(address(this)), balanceStETHBefore, "wrong stETH balance");
    }
}
