// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";
import { TransferLibrary } from "./utils/TransferLibrary.sol";

/**
 * @custom:feature Initiate a long position by using contracts for the transfer of wstETH
 * @custom:background The test contract has 1M wstETH and has fallback functions to transfer tokens
 */
contract TestForkUsdnProtocolInitiateOpenPositionWithFallback is TransferLibrary, UsdnProtocolBaseIntegrationFixture {
    uint128 constant DEPOSIT_AMOUNT = 2 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labeled `Fork`
        _setUp(params);
        deal(address(wstETH), address(this), 1e6 ether);
    }

    /**
     * @custom:scenario Initiate a new long by using fallback for the transfer of wstETH
     * @custom:given The user has wstETH
     * @custom:when The user initiates a new long of `DEPOSIT_AMOUNT` with a contract that has fallback to transfer
     * tokens
     * @custom:then The protocol receives `DEPOSIT_AMOUNT` wstETH
     */
    function test_ForkFFIInitiateOpenPositionWithWithFallback() public {
        transferActive = true;
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        (bool success,) = protocol.initiateOpenPosition{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT,
            params.initialPrice / 2,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            "",
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + DEPOSIT_AMOUNT);
    }

    /**
     * @custom:scenario Initiate a new long by using fallback without the transfer of wstETH
     * @custom:given The user has wstETH
     * @custom:when The user initiates a new long of `DEPOSIT_AMOUNT` with a contract that no transfer wstETH
     * @custom:then the protocol revert with `UsdnProtocolFallbackTransferFailed` error
     */
    function test_ForkFFIInitiateDepositFallbackWithoutWstETHTransfer() public {
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        uint256 leverage = protocol.getMaxLeverage();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolFallbackTransferFailed.selector));
        protocol.initiateOpenPosition{ value: securityDeposit }(
            DEPOSIT_AMOUNT,
            params.initialPrice / 2,
            leverage,
            address(this),
            payable(address(this)),
            "",
            EMPTY_PREVIOUS_DATA
        );
    }
}
