// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { PYTH_STETH_USD } from "test/utils/Constants.sol";
import { USER_1, USER_2 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validating a deposit through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterValidateDeposit is UniversalRouterBaseFixture {
    function setUp() public {
        _setUp();
        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        sdex.approve(address(protocol), type(uint256).max);
        // initiate deposit in the past
        vm.warp(block.timestamp - 120 minutes);
        protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            0.1 ether, USER_2, USER_1, "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Validating a deposit through the router
     * @custom:given The user has initiated a deposit and we have price know by the oracle
     * @custom:when The user validates a deposit through the router
     * @custom:then The deposit is validated successfully
     */
    function test_ForkValidateDeposit() public {
        uint256 ts1 = protocol.getUserPendingAction(USER_1).timestamp;
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_STETH_USD, ts1 + oracleMiddleware.getValidationDelay());
        vm.warp(ts1 + oracleMiddleware.getValidationDelay()); //to be realistic because not mandatory

        uint256 ethBalanceBefore = address(this).balance;
        uint256 ethBalanceBeforeUser = USER_1.balance;
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateDeposit);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.VALIDATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(USER_1, data, EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: validationCost }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - validationCost, "ether balance");
        assertEq(USER_1.balance, ethBalanceBeforeUser + protocol.getSecurityDepositValue(), "user balance");
        assertEq(usdn.sharesOf(address(this)), 0, "usdn shares");
        assertEq(usdn.sharesOf(USER_1), 0, "usdn shares USER_1");
        assertGt(usdn.sharesOf(USER_2), 0, "usdn shares USER_2");
    }
}
