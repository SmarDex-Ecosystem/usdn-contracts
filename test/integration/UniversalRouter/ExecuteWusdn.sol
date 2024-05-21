// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

import { UniversalRouterBaseIntegrationFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { DEPLOYER, WETH, SDEX, WSTETH } from "test/utils/Constants.sol";

/**
 * @custom:feature Test commands lower than first boundary of the `execute` function
 * @custom:background A initiated universal router
 */
contract TestExecuteFourthBoundary is UniversalRouterBaseIntegrationFixture {
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
     * @custom:given The router should be funded with some `usdn`
     * @custom:when The `execute` function is called for `WRAP_USDN` command
     * @custom:then The `WRAP_USDN` command should be executed
     * @custom:and The `usdn` user balance should be increased
     */
    function test_execute_wrap_usdn() external {
        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.WRAP_USDN) << (256 - 8)));

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
     * @custom:scenario Test the `UNWRAP_WUSDN` command using the router balance
     * @custom:given The initiated universal router
     * @custom:given The router should be funded with some `usdn`
     * @custom:when The `execute` function is called for `UNWRAP_WUSDN` command
     * @custom:then The `UNWRAP_WUSDN` command should be executed
     * @custom:and The `usdn` user balance should be increased
     */
    function test_execute_unwrap_usdn() external {
        wusdn.deposit(BASE_AMOUNT, address(this));
        uint256 wusdnBalance = wusdn.balanceOf(address(this));
        // commands
        bytes memory commands = abi.encodePacked(bytes1(bytes32(Commands.UNWRAP_WUSDN) << (256 - 8)));

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
}
