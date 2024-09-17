// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

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
     * @custom:then The protocol receives `DEPOSIT_AMOUNT` wstETH
     */
    function test_ForkFFIInitiateDepositWithFallback() public {
        transferActive = true;
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        bool success = protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT, DISABLE_SHARES_OUT_MIN, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + DEPOSIT_AMOUNT);
    }

    /**
     * @custom:scenario Initiate a deposit by using fallback without the transfer of Sdex
     * @custom:given The user has wstETH and SDEX
     * @custom:when The user initiates a deposit of `DEPOSIT_AMOUNT` with a contract that no transfer Sdex
     * @custom:then the protocol revert with `UsdnProtocolFallbackTransferFailed` error
     */
    function test_ForkFFIInitiateDepositFallbackWithoutSdexTransfer() public {
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolFallbackTransferFailed.selector));
        protocol.initiateDeposit{ value: securityDeposit }(
            DEPOSIT_AMOUNT, DISABLE_SHARES_OUT_MIN, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
    }
}
