// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

/**
 * @custom:feature Initiating an open position through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterInitiateOpenPosition is UniversalRouterBaseFixture {
    uint256 constant OPEN_POSITION_AMOUNT = 2 ether;
    uint256 constant DESIRED_LIQUIDATION = 2500 ether;

    function setUp() public {
        _setUp();
        deal(address(wstETH), address(this), OPEN_POSITION_AMOUNT * 2);
    }

    /**
     * @custom:scenario Initiating an open position through the router
     * @custom:given The user sent the exact amount of wstETH to the router
     * @custom:when The user initiates an open position through the router
     * @custom:then Open position is initiated successfully
     */
    function test_ForkInitiateOpenPosition() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 wstETHBefore = wstETH.balanceOf(address(this));

        wstETH.transfer(address(router), OPEN_POSITION_AMOUNT);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_OPEN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] =
            abi.encode(OPEN_POSITION_AMOUNT, DESIRED_LIQUIDATION, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
        assertEq(wstETH.balanceOf(address(this)), wstETHBefore - OPEN_POSITION_AMOUNT, "wstETH balance");
    }

    /**
     * @custom:scenario Initiating an open position through the router with a "full balance" amount
     * @custom:given The user sent the `OPEN_POSITION_AMOUNT` of wstETH to the router
     * @custom:when The user initiates an open position through the router with the amount `CONTRACT_BALANCE`
     * @custom:then The open position is initiated successfully with the full balance of the router
     * @custom:and The user's asset balance is reduced by `OPEN_POSITION_AMOUNT`
     */
    function test_ForkInitiateOpenPositionFullBalance() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 wstETHBefore = wstETH.balanceOf(address(this));

        wstETH.transfer(address(router), OPEN_POSITION_AMOUNT);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_OPEN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] =
            abi.encode(Constants.CONTRACT_BALANCE, DESIRED_LIQUIDATION, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
        assertEq(wstETH.balanceOf(address(this)), wstETHBefore - OPEN_POSITION_AMOUNT, "wstETH balance");
    }
}
