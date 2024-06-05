// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";
import { Payments } from "@uniswap/universal-router/contracts/modules/Payments.sol";
import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { DEPLOYER, WETH, SDEX, WSTETH } from "test/utils/Constants.sol";

/**
 * @custom:feature Test wrap and unwrap commands of the `execute` function
 * @custom:background A initiated universal router
 */
contract TestForkExecuteWusdn is UniversalRouterBaseFixture {
    uint256 constant BASE_AMOUNT = 1 ether;

    function setUp() external {
        _setUp();

        deal(WETH, address(this), BASE_AMOUNT * 1e3);
        deal(address(sdex), address(this), BASE_AMOUNT * 1e3);
        deal(address(wstETH), address(this), BASE_AMOUNT * 1e3);

        // mint usdn
        sdex.approve(address(protocol), type(uint256).max);
        wstETH.approve(address(protocol), type(uint256).max);
        usdn.approve(address(wusdn), type(uint256).max);

        bytes32 MINTER_ROLE = usdn.MINTER_ROLE();
        vm.prank(DEPLOYER);
        usdn.grantRole(MINTER_ROLE, address(this));
        usdn.mint(address(this), BASE_AMOUNT * 1e3);
    }

    /**
     * @custom:scenario Test the `WRAP_USDN` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `usdn`
     * @custom:when The `execute` function is called for `WRAP_USDN` command
     * @custom:then The `WRAP_USDN` command should be executed
     * @custom:and The `usdn` user balance should be increased
     */
    function test_ForkExecuteWrapUsdn() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.WRAP_USDN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.CONTRACT_BALANCE, Constants.MSG_SENDER);

        // transfer
        usdn.transfer(address(router), BASE_AMOUNT);
        uint256 balanceWusdnBefore = wusdn.balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(wusdn.balanceOf(address(this)), balanceWusdnBefore, "wrong wusdn balance");
    }

    /**
     * @custom:scenario Test the `WRAP_USDN` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `usdn`
     * @custom:when The `execute` function is called for `WRAP_USDN` command
     * @custom:then The transaction should revert with `InsufficientToken`
     */
    function test_RevertWhen_ForkExecuteWrapUsdnInsufficientToken() external {
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.WRAP_USDN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(BASE_AMOUNT + 1, Constants.MSG_SENDER);

        // transfer
        usdn.transfer(address(router), BASE_AMOUNT);

        // execution
        vm.expectRevert(Payments.InsufficientToken.selector);
        router.execute(commands, inputs);
    }

    /**
     * @custom:scenario Test the `UNWRAP_WUSDN` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `usdn`
     * @custom:when The `execute` function is called for `UNWRAP_WUSDN` command
     * @custom:then The `UNWRAP_WUSDN` command should be executed
     * @custom:and The `usdn` user balance should be increased
     */
    function test_ForkExecuteUnwrapUsdn() external {
        wusdn.deposit(BASE_AMOUNT, address(this));
        uint256 wusdnBalance = wusdn.balanceOf(address(this));
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.UNWRAP_WUSDN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.CONTRACT_BALANCE, Constants.MSG_SENDER, Constants.ADDRESS_THIS);

        // transfer
        wusdn.transfer(address(router), wusdnBalance);
        uint256 balanceUsdnBefore = usdn.balanceOf(address(this));

        // execution
        router.execute(commands, inputs);

        // assert
        assertGt(usdn.balanceOf(address(this)), balanceUsdnBefore, "wrong usdn balance");
    }

    /**
     * @custom:scenario Test the `UNWRAP_WUSDN` command using the router balance
     * @custom:given The initiated universal router
     * @custom:and The router should be funded with some `usdn`
     * @custom:when The `execute` function is called for `UNWRAP_WUSDN` command
     * @custom:then The transaction should revert with `InsufficientToken`
     */
    function test_RevertWhen_ForkExecuteUnwrapUsdnInsufficientToken() external {
        wusdn.deposit(BASE_AMOUNT, address(this));
        uint256 wusdnBalance = wusdn.balanceOf(address(this));
        // commands
        bytes memory commands = abi.encodePacked(uint8(Commands.UNWRAP_WUSDN));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(wusdnBalance + 1, Constants.MSG_SENDER, Constants.ADDRESS_THIS);

        // transfer
        wusdn.transfer(address(router), wusdnBalance);

        // execution
        vm.expectRevert(Payments.InsufficientToken.selector);
        router.execute(commands, inputs);
    }
}
