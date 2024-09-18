// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { TransferLibrary } from "../utils/TransferLibrary.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiateDeposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsInitiateDepositWithCallback is TransferLibrary, UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant POSITION_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);

        // Sanity check
        assertGt(protocol.getSdexBurnOnDepositRatio(), 0, "USDN to SDEX burn ratio should not be 0");

        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Initiate a deposit by using callback for tokens transfer
     * @custom:given The user has wstETH and SDEX
     * @custom:when The user initiates a deposit of `POSITION_AMOUNT` with a contract that has callback to transfer
     * tokens
     * @custom:then The protocol receives `POSITION_AMOUNT` wstETH and dead address receives SDEX
     */
    function test_InitiateDepositWithCallback() public {
        transferActive = true;
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        uint256 balanceSdexBefore = sdex.balanceOf(address(this));
        uint256 deadBalanceSdexBefore = sdex.balanceOf(Constants.DEAD_ADDRESS);
        bool success = protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            POSITION_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(uint128(2000 ether)),
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + POSITION_AMOUNT);
        assertLt(sdex.balanceOf(address(this)), balanceSdexBefore);
        assertGt(sdex.balanceOf(Constants.DEAD_ADDRESS), deadBalanceSdexBefore);
    }

    /**
     * @custom:scenario Initiate a deposit by using callback without token transfer
     * @custom:given The user has wstETH and SDEX
     * @custom:when The user initiates a deposit of `POSITION_AMOUNT` with a contract that no transfer tokens
     * @custom:then the protocol revert with `UsdnProtocolPaymentCallbackFailed` error
     */
    function test_InitiateDepositCallbackWithoutSdexTransfer() public {
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.initiateDeposit{ value: securityDeposit }(
            POSITION_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(uint128(2000 ether)),
            EMPTY_PREVIOUS_DATA
        );
    }
}
