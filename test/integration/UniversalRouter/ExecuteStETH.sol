// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { ForkUniversalRouterBaseIntegrationFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { IStETH } from "src/UniversalRouter/interfaces/IStETH.sol";

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
        stETH.transferShares(address(router), stETH.sharesOf(address(this)));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.WRAP_STETH)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER);

        // execution
        router.execute(commands, inputs);

        // assert
        assertApproxEqAbs(
            wstETH.balanceOf(address(this)),
            stETH.getPooledEthByShares(stETH.getSharesByPooledEth(BASE_AMOUNT)),
            1,
            "wrong wstETH balance(user)"
        );
        assertEq(stETH.sharesOf(address(this)), 0, "wrong stETH balance(user)");
        assertEq(wstETH.balanceOf(address(router)), 0, "wrong wstETH balance(router)");
        assertApproxEqAbs(stETH.sharesOf(address(router)), 0, 1, "wrong stETH balance(router)");
    }

    /**
     * @custom:scenario Test the `WRAP_STETH` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `stETH`
     * @custom:when The `execute` function is called for `WRAP_STETH` command
     * @custom:then The `WRAP_STETH` command should be executed
     * @custom:and The `wsteth` router balance should be increased
     */
    function test_executeWrapStETHForRouter() external {
        // unwrap
        wstETH.unwrap(BASE_AMOUNT);
        stETH.transferShares(address(router), stETH.sharesOf(address(this)));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.WRAP_STETH)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.ADDRESS_THIS);

        // execution
        router.execute(commands, inputs);

        // assert
        assertApproxEqAbs(
            wstETH.balanceOf(address(router)),
            stETH.getPooledEthByShares(stETH.getSharesByPooledEth(BASE_AMOUNT)),
            1,
            "wrong wstETH balance(router)"
        );
        assertApproxEqAbs(stETH.sharesOf(address(router)), 0, 1, "wrong stETH balance(router)");
        assertEq(wstETH.balanceOf(address(this)), 0, "wrong wstETH balance(user)");
        assertEq(stETH.sharesOf(address(this)), 0, "wrong stETH balance(user)");
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
        uint256 sharesOfStETHBefore = stETH.sharesOf(address(this));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.UNWRAP_WSTETH)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, stETH.getPooledEthByShares(BASE_AMOUNT));

        // execution
        router.execute(commands, inputs);

        // assert
        assertEq(
            stETH.sharesOf(address(this)),
            sharesOfStETHBefore + stETH.getSharesByPooledEth(stETH.getPooledEthByShares(BASE_AMOUNT)),
            "wrong stETH balance(user)"
        );
        assertEq(wstETH.balanceOf(address(this)), 0, "wrong wstETH balance(user)");
        assertEq(stETH.sharesOf(address(router)), 0, "wrong stETH balance(router)");
        assertEq(wstETH.balanceOf(address(router)), 0, "wrong wstETH balance(router)");
    }

    /**
     * @custom:scenario Test the `UNWRAP_WSTETH` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `wstETH`
     * @custom:when The `execute` function is called for `UNWRAP_WSTETH` command
     * @custom:then The `UNWRAP_WSTETH` command should be executed
     * @custom:and The `stETH` router balance should be increased
     */
    function test_executeUnwrapStETHForRouter() external {
        // transfer
        wstETH.transfer(address(router), BASE_AMOUNT);
        uint256 sharesOfStETHBefore = stETH.sharesOf(address(this));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.UNWRAP_WSTETH)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.ADDRESS_THIS, stETH.getPooledEthByShares(BASE_AMOUNT));

        // execution
        router.execute(commands, inputs);

        // assert
        assertEq(
            stETH.sharesOf(address(router)),
            sharesOfStETHBefore + stETH.getSharesByPooledEth(stETH.getPooledEthByShares(BASE_AMOUNT)),
            "wrong stETH balance(router)"
        );
        assertEq(wstETH.balanceOf(address(router)), 0, "wrong wstETH balance(router)");
        assertEq(stETH.sharesOf(address(this)), 0, "wrong stETH balance(user)");
        assertEq(wstETH.balanceOf(address(this)), 0, "wrong wstETH balance(user)");
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
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.UNWRAP_WSTETH)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.MSG_SENDER, stETH.getPooledEthByShares(1) + 1);

        // execution
        vm.expectRevert(InsufficientToken.selector);
        router.execute(commands, inputs);
    }
}
