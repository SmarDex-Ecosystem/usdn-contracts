// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PYTH_ETH_USD } from "test/utils/Constants.sol";
import { USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { ProtocolAction, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Validating a close position through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterValidateClosePosition is UniversalRouterBaseFixture {
    using SafeCast for uint256;

    uint256 constant OPEN_POSITION_AMOUNT = 2 ether;
    uint256 constant DESIRED_LIQUIDATION = 2500 ether;
    uint256 internal _securityDeposit;

    function setUp() public {
        _setUp();
        deal(address(wstETH), address(this), OPEN_POSITION_AMOUNT * 2);
        wstETH.approve(address(protocol), type(uint256).max);
        _securityDeposit = protocol.getSecurityDepositValue();
        (, PositionId memory posId) = protocol.initiateOpenPosition{ value: _securityDeposit }(
            OPEN_POSITION_AMOUNT.toUint128(),
            DESIRED_LIQUIDATION.toUint128(),
            address(this),
            address(this),
            "",
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay(); // to be realistic because not mandatory
        uint256 ts1 = protocol.getUserPendingAction(address(this)).timestamp;
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, ts1 + oracleMiddleware.getValidationDelay());
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateOpenPosition);
        protocol.validateOpenPosition{ value: validationCost }(address(this), data, EMPTY_PREVIOUS_DATA);
        protocol.initiateClosePosition{ value: _securityDeposit }(
            posId, OPEN_POSITION_AMOUNT.toUint128(), USER_1, "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Validating a close position through the router
     * @custom:given The user has initiated a close position
     * @custom:when The user validates a close position through the router
     * @custom:then The close position is validated successfully
     */
    function test_ForkValidateClosePosition() public {
        _waitDelay(); // to be realistic because not mandatory
        uint256 ts1 = protocol.getUserPendingAction(address(this)).timestamp;
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, ts1 + oracleMiddleware.getValidationDelay());

        uint256 ethBalanceBefore = address(this).balance;
        uint256 wstETHBalanceBefore = wstETH.balanceOf(address(this));
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.ValidateClosePosition);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.VALIDATE_CLOSE)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), data, EMPTY_PREVIOUS_DATA, validationCost);
        router.execute{ value: validationCost }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - validationCost + _securityDeposit, "ether balance");
        assertEq(wstETH.balanceOf(address(this)), wstETHBalanceBefore, "wstETH balance");
        assertApproxEqRel(wstETH.balanceOf(USER_1), OPEN_POSITION_AMOUNT, 1e16, "wstETH balance USER_1 with delta 1%");
    }

    receive() external payable { }
}
