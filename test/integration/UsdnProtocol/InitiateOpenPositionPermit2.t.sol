// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";

/**
 * @custom:feature Initiate a long position by using Permit2 for the transfer of wstETH
 * @custom:background The test contract has 1M wstETH and has approved Permit2 to spend all of them
 */
contract TestForkUsdnProtocolInitiateOpenPositionPermit2 is UsdnProtocolBaseIntegrationFixture {
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(SafeTransferLib.PERMIT2);
    uint128 constant DEPOSIT_AMOUNT = 2 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labeled `Fork`
        _setUp(params);
        deal(address(wstETH), address(this), 1e6 ether);
        wstETH.approve(address(PERMIT2), type(uint256).max);
    }

    /**
     * @custom:scenario Initiate a new long by using Permit2 for the transfer of wstETH
     * @custom:given The user has approved the protocol to spend `DEPOSIT_AMOUNT` wstETH through Permit2
     * @custom:when The user initiates a new long of `DEPOSIT_AMOUNT` by setting the asset bit in the bitfield
     * @custom:then The protocol receives `DEPOSIT_AMOUNT` wstETH
     */
    function test_ForkFFIInitiateOpenPositionWithPermit2() public {
        PERMIT2.approve(address(wstETH), address(protocol), DEPOSIT_AMOUNT, type(uint48).max);
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        (bool success,) = protocol.initiateOpenPosition{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT,
            params.initialPrice / 2,
            type(uint128).max,
            address(this),
            payable(address(this)),
            Permit2TokenBitfield.Bitfield.wrap(Permit2TokenBitfield.ASSET_MASK),
            "",
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + DEPOSIT_AMOUNT);
    }
}
