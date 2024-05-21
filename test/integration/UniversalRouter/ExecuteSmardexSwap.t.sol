// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

import { UniversalRouterBaseIntegrationFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";
import { WETH, SDEX } from "test/utils/Constants.sol";

/**
 * @custom:feature Test smardex swap commands
 * @custom:background A initiated universal router
 */
contract TestExecuteSmardexSwap is UniversalRouterBaseIntegrationFixture {
    uint256 constant BASE_AMOUNT = 1 ether;

    function setUp() external {
        _setUp();

        deal(WETH, address(this), BASE_AMOUNT * 1e3);
        deal(address(sdex), address(this), BASE_AMOUNT * 1e3);
    }

    /**
     * @custom:scenario Test the `` command using the router balance
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some sdex
     * @custom:when The `execute` function is called for `` command
     * @custom:then The `` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_execute_smardex_swap_exact_in() external {
        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.SMARDEX_SWAP_EXACT_IN) << (256 - 8)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), BASE_AMOUNT, 0, abi.encodePacked(SDEX, WETH), false);

        // transfer
        sdex.transfer(address(router), BASE_AMOUNT);
        uint256 balanceWethBefore = IERC20(WETH).balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(IERC20(WETH).balanceOf(address(this)), balanceWethBefore, "wrong weth balance");
    }
}
