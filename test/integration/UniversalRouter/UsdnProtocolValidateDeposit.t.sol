// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { PYTH_STETH_USD } from "test/utils/Constants.sol";
import { USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { ProtocolAction, PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validating a deposit through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterValidateDeposit is UniversalRouterBaseFixture {
    uint128 constant DEPOSIT_AMOUNT = 0.1 ether;

    function setUp() public {
        _setUp();
        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        sdex.approve(address(protocol), type(uint256).max);
        // initiate deposit in
        vm.warp(block.timestamp - 120 minutes); // -2H
        protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT, address(this), address(this), "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Validating a deposit through the router
     * @custom:given The user use the router
     * @custom:when The user initiates a deposit through the router
     * @custom:then The deposit is initiated successfully
     */
    function test_ForkValidateDeposit() public {
        uint256 ts1 = protocol.getUserPendingAction(address(this)).timestamp;
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_STETH_USD, ts1 + oracleMiddleware.getValidationDelay());
        vm.warp(ts1 + oracleMiddleware.getValidationDelay()); //to be realistic because not mandatory
        uint256 ethBalanceBefore = address(this).balance;
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateDeposit);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.VALIDATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), data, EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: validationCost }(commands, inputs);

        assertEq(
            address(this).balance,
            ethBalanceBefore + protocol.getSecurityDepositValue() - validationCost,
            "ether balance"
        );
        assertGt(usdn.sharesOf(address(this)), 0, "usdn shares");
    }

    receive() external payable { }
}
