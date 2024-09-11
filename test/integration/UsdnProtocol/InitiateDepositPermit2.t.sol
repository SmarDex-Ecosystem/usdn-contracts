// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";

/**
 * @custom:feature Initiate a deposit by using Permit2 for the transfer of wstETH and SDEX
 * @custom:background The test contract has 1M wstETH and 1M SDEX and has approved Permit2 to spend all of them
 */
contract TestForkUsdnProtocolInitiateDepositPermit2 is UsdnProtocolBaseIntegrationFixture {
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(SafeTransferLib.PERMIT2);
    uint128 constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labeled `Fork`
        _setUp(params);
        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
        wstETH.approve(address(PERMIT2), type(uint256).max);
        sdex.approve(address(PERMIT2), type(uint256).max);
    }

    /**
     * @custom:scenario Initiate a deposit by using Permit2 for the transfer of wstETH
     * @custom:given The user has approved the protocol to spend `DEPOSIT_AMOUNT` wstETH through Permit2
     * @custom:when The user initiates a deposit of `DEPOSIT_AMOUNT` by setting the asset bit in the bitfield
     * @custom:then The protocol receives `DEPOSIT_AMOUNT` wstETH
     */
    function test_ForkFFIInitiateDepositWithPermit2ForAsset() public {
        PERMIT2.approve(address(wstETH), address(protocol), DEPOSIT_AMOUNT, type(uint48).max);
        sdex.approve(address(protocol), type(uint256).max);
        uint256 balanceBefore = wstETH.balanceOf(address(protocol));
        bool success = protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            Permit2TokenBitfield.Bitfield.wrap(Permit2TokenBitfield.ASSET_MASK),
            "",
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), balanceBefore + DEPOSIT_AMOUNT);
    }

    /**
     * @custom:scenario Initiate a deposit by using Permit2 for the transfer of SDEX
     * @custom:given The user has approved the protocol to spend all SDEX through Permit2
     * @custom:when The user initiates a deposit by setting the SDEX bit in the bitfield
     * @custom:then The dead address receives some SDEX
     */
    function test_ForkFFIInitiateDepositWithPermit2ForSdex() public {
        wstETH.approve(address(protocol), type(uint256).max);
        PERMIT2.approve(address(sdex), address(protocol), type(uint160).max, type(uint48).max);
        uint256 balanceBefore = sdex.balanceOf(protocol.DEAD_ADDRESS());
        bool success = protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            Permit2TokenBitfield.Bitfield.wrap(Permit2TokenBitfield.SDEX_MASK),
            "",
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertGt(sdex.balanceOf(protocol.DEAD_ADDRESS()), balanceBefore);
    }

    /**
     * @custom:scenario Initiate a deposit by using Permit2 for the transfer of wstETH and SDEX
     * @custom:given The user has approved the protocol to spend `DEPOSIT_AMOUNT` wstETH and all SDEX through Permit2
     * @custom:when The user initiates a deposit by setting the asset and SDEX bits in the bitfield
     * @custom:then The protocol receives `DEPOSIT_AMOUNT` wstETH and the dead address receives some SDEX
     */
    function test_ForkFFIInitiateDepositWithPermit2ForBoth() public {
        PERMIT2.approve(address(wstETH), address(protocol), DEPOSIT_AMOUNT, type(uint48).max);
        PERMIT2.approve(address(sdex), address(protocol), type(uint160).max, type(uint48).max);
        uint256 assetBalanceBefore = wstETH.balanceOf(address(protocol));
        uint256 sdexBalanceBefore = sdex.balanceOf(protocol.DEAD_ADDRESS());
        bool success = protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
            DEPOSIT_AMOUNT,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            Permit2TokenBitfield.Bitfield.wrap(Permit2TokenBitfield.ASSET_MASK | Permit2TokenBitfield.SDEX_MASK),
            "",
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(wstETH.balanceOf(address(protocol)), assetBalanceBefore + DEPOSIT_AMOUNT);
        assertGt(sdex.balanceOf(protocol.DEAD_ADDRESS()), sdexBalanceBefore);
    }
}
