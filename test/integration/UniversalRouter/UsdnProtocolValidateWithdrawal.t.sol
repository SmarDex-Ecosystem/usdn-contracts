// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PYTH_ETH_USD } from "../../utils/Constants.sol";
import { DEPLOYER, USER_1, USER_2 } from "../../utils/Constants.sol";
import { UniversalRouterBaseFixture } from "./utils/Fixtures.sol";

import { Commands } from "../../../src/UniversalRouter/libraries/Commands.sol";
import { ProtocolAction } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validating a withdrawal through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterValidateWithdrawal is UniversalRouterBaseFixture {
    using SafeCast for uint256;

    uint256 internal WITHDRAW_AMOUNT;
    uint256 internal _securityDeposit;

    function setUp() public {
        _setUp();
        WITHDRAW_AMOUNT = usdn.sharesOf(DEPLOYER) / 100;
        vm.prank(DEPLOYER);
        usdn.transferShares(address(this), WITHDRAW_AMOUNT);
        usdn.approve(address(protocol), type(uint256).max);
        _securityDeposit = protocol.getSecurityDepositValue();
        protocol.initiateWithdrawal{ value: _securityDeposit }(
            WITHDRAW_AMOUNT.toUint152(), USER_2, USER_1, "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Validating a withdrawal through the router
     * @custom:given The user has initiated a withdrawal
     * @custom:when The user validates a withdrawal through the router
     * @custom:then The withdrawal is validated successfully
     */
    function test_ForkValidateWithdraw() public {
        _waitDelay(); // to be realistic because not mandatory
        uint256 ts1 = protocol.getUserPendingAction(USER_1).timestamp;
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, ts1 + oracleMiddleware.getValidationDelay());

        uint256 ethBalanceBefore = address(this).balance;
        uint256 ethBalanceBeforeUser = USER_1.balance;
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateWithdrawal);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.VALIDATE_WITHDRAWAL)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(USER_1, data, EMPTY_PREVIOUS_DATA, validationCost);
        router.execute{ value: validationCost }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - validationCost, "ether balance");
        assertEq(USER_1.balance, ethBalanceBeforeUser + _securityDeposit, "user balance");
        assertEq(wstETH.balanceOf(address(this)), 0, "wstETH balance");
        assertEq(wstETH.balanceOf(USER_1), 0, "wstETH balance USER_1");
        assertGt(wstETH.balanceOf(USER_2), 0, "wstETH balance USER_2");
    }
}
