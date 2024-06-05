// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { SmardexSwapRouter } from "src/UniversalRouter/modules/smardex/SmardexSwapRouter.sol";

import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";
import { WETH, SDEX, WBTC } from "test/utils/Constants.sol";

/**
 * @custom:feature Test smardex swap commands
 * @custom:background A initiated universal router
 */
contract TestExecuteSmardexSwap is UniversalRouterBaseFixture {
    uint256 constant BASE_AMOUNT = 1 ether;

    function setUp() external {
        _setUp();

        deal(WETH, address(this), BASE_AMOUNT * 1e3);
        deal(SDEX, address(this), BASE_AMOUNT * 1e3);
        deal(WBTC, address(this), BASE_AMOUNT * 1e3);
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_IN` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_IN` command
     * @custom:then The `SMARDEX_SWAP_EXACT_IN` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactInBalance() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_IN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, Constants.CONTRACT_BALANCE, 0, abi.encodePacked(SDEX, WETH), false);

        // transfer
        sdex.transfer(address(router), BASE_AMOUNT);
        uint256 balanceWethBefore = IERC20(WETH).balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(IERC20(WETH).balanceOf(address(this)), balanceWethBefore, "wrong weth balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_IN` command using the router balance by multi hops
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some wbtc
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_IN` command
     * @custom:then The `SMARDEX_SWAP_EXACT_IN` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactInBalanceMulti() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_IN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] =
            abi.encode(Constants.MSG_SENDER, Constants.CONTRACT_BALANCE, 0, abi.encodePacked(WBTC, WETH, SDEX), false);

        // transfer
        IERC20(WBTC).transfer(address(router), 1e10);
        uint256 balanceSdexBefore = IERC20(SDEX).balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(IERC20(SDEX).balanceOf(address(this)), balanceSdexBefore, "wrong sdex balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_IN` command using permit2
     * @custom:given The initiated universal router
     * @custom:and The user should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_IN` command
     * @custom:then The `SMARDEX_SWAP_EXACT_IN` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactInPermit2() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_IN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, BASE_AMOUNT, 0, abi.encodePacked(SDEX, WETH), true);

        // permit2 approve
        IERC20(SDEX).approve(address(permit2), type(uint256).max);
        permit2.approve(SDEX, address(router), type(uint160).max, type(uint48).max);
        uint256 balanceWethBefore = IERC20(WETH).balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(IERC20(WETH).balanceOf(address(this)), balanceWethBefore, "wrong weth balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_IN` command using permit2 by multi hops
     * @custom:given The initiated universal router
     * @custom:and The user should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_IN` command
     * @custom:then The `SMARDEX_SWAP_EXACT_IN` command should be executed
     * @custom:and The sdex user balance should be increased
     */
    function test_executeSmardexSwapExactInPermit2Multi() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_IN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, BASE_AMOUNT, 0, abi.encodePacked(WBTC, WETH, SDEX), true);

        // permit2 approve
        IERC20(WBTC).approve(address(permit2), type(uint256).max);
        permit2.approve(WBTC, address(router), type(uint160).max, type(uint48).max);
        uint256 balanceSdexBefore = IERC20(SDEX).balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(IERC20(SDEX).balanceOf(address(this)), balanceSdexBefore, "wrong sdex balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_IN` command using permit2 by multi hops
     * @custom:given The initiated universal router
     * @custom:and The user should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_IN` command
     * @custom:then The `SMARDEX_SWAP_EXACT_IN` command should be executed
     * @custom:and The sdex user balance should be increased
     */
    function test_RevertWhen_executeSmardexSwapExactInAmountMin() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_IN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            Constants.MSG_SENDER, Constants.CONTRACT_BALANCE, type(uint256).max, abi.encodePacked(SDEX, WETH), false
        );

        // transfer
        sdex.transfer(address(router), BASE_AMOUNT);

        // execution
        vm.expectRevert(SmardexSwapRouter.tooLittleReceived.selector);
        router.execute(commands, inputs);
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_OUT` command using the router balance
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_OUT` command
     * @custom:then The `SMARDEX_SWAP_EXACT_OUT` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactOutBalance() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_OUT));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, BASE_AMOUNT, BASE_AMOUNT, abi.encodePacked(WETH, SDEX), false);

        // transfer
        IERC20(WETH).transfer(address(router), BASE_AMOUNT);
        uint256 balanceSdexBefore = sdex.balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(sdex.balanceOf(address(this)), balanceSdexBefore, "wrong sdex balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_OUT` command using the router balance by multi hops
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_OUT` command
     * @custom:then The `SMARDEX_SWAP_EXACT_OUT` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactOutBalanceMulti() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_OUT));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] =
            abi.encode(Constants.MSG_SENDER, BASE_AMOUNT, BASE_AMOUNT, abi.encodePacked(WBTC, WETH, SDEX), false);

        // transfer
        IERC20(WBTC).transfer(address(router), BASE_AMOUNT);
        uint256 balanceSdexBefore = sdex.balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(sdex.balanceOf(address(this)), balanceSdexBefore, "wrong sdex balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_OUT` command using permit2
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_OUT` command
     * @custom:then The `SMARDEX_SWAP_EXACT_OUT` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactOutPermit2() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_OUT));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, BASE_AMOUNT, BASE_AMOUNT, abi.encodePacked(WETH, SDEX), true);

        // permit2 approve
        IERC20(WETH).approve(address(permit2), type(uint256).max);
        permit2.approve(WETH, address(router), type(uint160).max, type(uint48).max);
        uint256 balanceSdexBefore = sdex.balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(sdex.balanceOf(address(this)), balanceSdexBefore, "wrong sdex balance");
    }

    /**
     * @custom:scenario Test the `SMARDEX_SWAP_EXACT_OUT` command using permit2 by multi hops
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some sdex
     * @custom:when The `execute` function is called for `SMARDEX_SWAP_EXACT_OUT` command
     * @custom:then The `SMARDEX_SWAP_EXACT_OUT` command should be executed
     * @custom:and The weth user balance should be increased
     */
    function test_executeSmardexSwapExactOutPermit2Multi() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.SMARDEX_SWAP_EXACT_OUT));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, BASE_AMOUNT, BASE_AMOUNT, abi.encodePacked(WBTC, WETH, SDEX), true);

        // permit2 approve
        IERC20(WBTC).approve(address(permit2), type(uint256).max);
        permit2.approve(WBTC, address(router), type(uint160).max, type(uint48).max);
        uint256 balanceSdexBefore = IERC20(SDEX).balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(sdex.balanceOf(address(this)), balanceSdexBefore, "wrong sdex balance");
    }
}
