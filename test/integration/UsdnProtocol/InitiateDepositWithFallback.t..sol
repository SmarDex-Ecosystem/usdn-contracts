// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";
import { TransferLibrary } from "./utils/TransferLibrary.sol";

/**
 * @custom:feature Initiate a deposit by using contracts for the transfer of wstETH and SDEX
 * @custom:background The test contract has 1M wstETH and 1M SDEX and has fallback functions to transfer tokens
 */
contract TestForkUsdnProtocolInitiateDepositWithFallback is TransferLibrary, UsdnProtocolBaseIntegrationFixture {
    uint128 constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labeled `Fork`
        _setUp(params);
        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
    }

    /**
     * @custom:scenario Initiate a deposit by using fallback for the transfer of wstETH and Sdex
     * @custom:given The user has wstETH and SDEX
     * @custom:when The user initiates a deposit of `DEPOSIT_AMOUNT` with a contract that has fallback to transfer
     * tokens
     * @custom:then The protocol receives `DEPOSIT_AMOUNT` wstETH and dead address receives SDEX
     */
    function test_ForkFFIInitiateDepositWithFallback() public {
        transferActive = true;
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        uint256 balanceSdexBefore = sdex.balanceOf(address(this));
        uint256 deadBalanceSdexBefore = sdex.balanceOf(Constants.DEAD_ADDRESS);
        bool success = protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT, DISABLE_SHARES_OUT_MIN, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + DEPOSIT_AMOUNT);
        assertLt(sdex.balanceOf(address(this)), balanceSdexBefore);
        assertGt(sdex.balanceOf(Constants.DEAD_ADDRESS), deadBalanceSdexBefore);
    }

    /**
     * @custom:scenario Initiate a deposit by using fallback without token transfer
     * @custom:given The user has wstETH and SDEX
     * @custom:when The user initiates a deposit of `DEPOSIT_AMOUNT` with a contract that no transfer tokens
     * @custom:then the protocol revert with `UsdnProtocolPaymentCallbackFailed` error
     */
    function test_ForkFFIInitiateDepositFallbackWithoutSdexTransfer() public {
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.initiateDeposit{ value: securityDeposit }(
            DEPOSIT_AMOUNT, DISABLE_SHARES_OUT_MIN, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
    }
}
