// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { TransferLibrary } from "../utils/TransferLibrary.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiateOpenPosition function of the UsdnProtocolActions contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsInitiateOpenPosition is TransferLibrary, UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant CURRENT_PRICE = 2000 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Initiate a new long by using callback for the transfer of wstETH
     * @custom:given The user has wstETH
     * @custom:when The user initiates a new long of `2 ether` with a contract that has callback to transfer
     * tokens
     * @custom:then The protocol receives `2 ether` wstETH
     */
    function test_InitiateOpenPositionWithCallback() public {
        transferActive = true;
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        (bool success,) = protocol.initiateOpenPosition{ value: protocol.getSecurityDepositValue() }(
            2 ether,
            CURRENT_PRICE / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + 2 ether);
    }

    /**
     * @custom:scenario Initiate a new long by using callback without the transfer of wstETH
     * @custom:given The user has wstETH
     * @custom:when The user initiates a new long of `2 ether` with a contract that no transfer wstETH
     * @custom:then the protocol revert with `UsdnProtocolPaymentCallbackFailed` error
     */
    function test_InitiateDepositCallbackWithoutWstETHTransfer() public {
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.initiateOpenPosition{ value: securityDeposit }(
            2 ether,
            CURRENT_PRICE / 2,
            type(uint128).max,
            leverage,
            address(this),
            payable(address(this)),
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );
    }
}
