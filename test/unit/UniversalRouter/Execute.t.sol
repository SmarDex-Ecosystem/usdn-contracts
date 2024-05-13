// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UniversalRouterBaseFixture } from "test/unit/UniversalRouter/utils/Fixtures.sol";
import { Commands } from "src/UniversalRouter/libraries/Commands.sol";

/**
 * @custom:feature Test the `execute` function of the actions universal router
 * @custom:background A initiated universal router
 */
contract TestExecute is UniversalRouterBaseFixture {
    function setUp() external {
        _setUp(EMPTY_PARAMS);
    }

    /**
     * @custom:scenario Test the transfer eth of the `execute` function
     * @custom:given The initiated universal router
     * @custom:and 100 ethers was sent to router
     * @custom:when the `execute` function is called for `TRANSFER` command
     * @custom:then the 100 ether should be transferred back to the test contract address
     */
    function test_execute_transfer_ether() external {
        uint256 amount = 100 ether;

        // commands
        bytes1 transferCommand = bytes1(bytes32(Commands.TRANSFER) << (256 - 8));
        bytes memory commands = abi.encodePacked(transferCommand);

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(0), address(this), amount);

        (bool success,) = address(router).call{ value: amount }("");
        assertTrue(success, "eth transfer error");

        uint256 balanceBefore = address(this).balance;
        router.execute(commands, inputs);

        assertEq(address(this).balance - balanceBefore, amount, "router transfer error");
    }

    // allow receive ether
    receive() external payable { }
}
