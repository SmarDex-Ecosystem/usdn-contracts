// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

contract TestForkUniversalRouterInitiateWithdraw is UniversalRouterBaseFixture {
    uint128 constant WITHDRAW_AMOUNT = 0.1 ether;

    function setUp() public {
        _setUp();
        vm.prank(DEPLOYER);
        usdn.transfer(address(this), WITHDRAW_AMOUNT);
    }

    function test_ForkInitiateWithdraw() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

        // send funds to router
        usdn.transfer(address(router), WITHDRAW_AMOUNT);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_WITHDRAWAL)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(WITHDRAW_AMOUNT, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
        assertEq(usdn.balanceOf(address(this)), usdnBalanceBefore - WITHDRAW_AMOUNT, "asset balance");
    }
}
