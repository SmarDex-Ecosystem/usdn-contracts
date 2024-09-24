// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature UserMaxPrice below the current price and tx reverts
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUsdnProtocolUserMaxPriceSlippage is UsdnProtocolBaseIntegrationFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.fork = true; // all tests in this contract must be labeled `Fork`
        params.forkWarp = 1_717_452_000; // Mon Jun 03 2024 22:00:00 UTC
        params.forkBlock = 20_014_134;
        _setUp(params);
    }

    /**
     * @custom:scenario UserMaxPrice is less than the current price and the transaction reverts
     * @custom:given The user has signed transaction in the past and now the current price(~3700$) is higher than the
     * userMaxPrice
     * @custom:when The transaction was received by the protocol with a userMaxPrice equal to 3001$
     * @custom:then The transaction reverts with a `UsdnProtocolSlippageMaxPriceExceeded` error
     */
    function test_ForkFFIUserMaxPriceLessThanCurrentPrice() public {
        uint256 leverage = protocol.getMaxLeverage();
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        vm.expectRevert(UsdnProtocolSlippageMaxPriceExceeded.selector);
        protocol.initiateOpenPosition{ value: securityDeposit }(
            2.5 ether,
            3000 ether,
            3001 ether,
            leverage,
            address(this),
            payable(address(this)),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );
    }
}
