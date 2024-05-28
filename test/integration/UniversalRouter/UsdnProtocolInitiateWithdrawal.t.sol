// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { DEPLOYER, USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

/**
 * @custom:feature Initiating a withdrawal through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterInitiateWithdrawal is UniversalRouterBaseFixture {
    uint256 constant WITHDRAW_AMOUNT = 1000;

    function setUp() public {
        _setUp();
        vm.prank(DEPLOYER);
        usdn.transferShares(address(this), WITHDRAW_AMOUNT);
    }

    /**
     * @custom:scenario Initiating a withdrawal through the router
     * @custom:given The user sent the exact amount of USDN to the router
     * @custom:when The user initiates a withdrawal through the router
     * @custom:then The withdrawal is initiated successfully
     */
    function test_ForkInitiateWithdraw() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.sharesOf(address(this));

        // send funds to router
        usdn.transferShares(address(router), WITHDRAW_AMOUNT);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_WITHDRAWAL)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(WITHDRAW_AMOUNT, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
        assertEq(usdn.sharesOf(address(this)), usdnBalanceBefore - WITHDRAW_AMOUNT, "asset balance");
    }

    /**
     * @custom:scenario Initiating a withdrawal through the router with a "full balance" amount
     * @custom:given The user sent the `WITHDRAW_AMOUNT` of USDN to the router
     * @custom:when The user initiates a withdrawal through the router with amount `CONTRACT_BALANCE`
     * @custom:then The withdrawal is initiated successfully with the full balance of the router
     * @custom:and The user's asset balance is reduced by `WITHDRAW_AMOUNT`
     */
    function test_ForkInitiateWithdrawFullBalance() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.sharesOf(address(this));

        // send funds to router
        usdn.transferShares(address(router), WITHDRAW_AMOUNT);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_WITHDRAWAL)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.CONTRACT_BALANCE, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
        assertEq(usdn.sharesOf(address(this)), usdnBalanceBefore - WITHDRAW_AMOUNT, "asset balance");
    }
}
