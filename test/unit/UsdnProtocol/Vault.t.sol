// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Test the functions in the vault contract
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolVault is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the calculation the amount of SDEX tokens to burn depending on the amount of USDN
     * @custom:given An amount of USDN to be minted
     * @custom:when The function is called with this amount
     * @custom:then The correct amount of SDEX to burn is returned
     */
    function test_calcSdexToBurn() public {
        uint256 burnRatio = protocol.getSdexBurnOnDepositRatio();
        uint256 burnRatioDivisor = protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR();
        uint8 usdnDecimals = protocol.TOKENS_DECIMALS();
        uint256 usdnToMint = 100 * 10 ** usdnDecimals;

        uint256 expectedSdexToBurn = usdnToMint * burnRatio / burnRatioDivisor;
        uint256 sdexToBurn = protocol.i_calcSdexToBurn(usdnToMint);
        assertEq(sdexToBurn, expectedSdexToBurn, "Result does not match the expected value");

        usdnToMint = 1_582_309 * 10 ** (usdnDecimals - 2);
        expectedSdexToBurn = usdnToMint * burnRatio / burnRatioDivisor;
        sdexToBurn = protocol.i_calcSdexToBurn(usdnToMint);
        assertEq(
            sdexToBurn,
            expectedSdexToBurn,
            "Result does not match expected value when the usdn to mint value is less round"
        );
    }

    /**
     * @custom:scenario Check the splitting of the withdrawal shares amount into two parts
     * @custom:given An amount to be split in the range of uint152
     * @custom:when The amount is split with the protocol function and then merged back
     * @custom:then The original amount should be the same as the input
     * @param amount The amount to be split and merged
     */
    function testFuzz_withdrawalAmountSplitting(uint152 amount) public {
        uint24 lsb = protocol.i_calcWithdrawalAmountLSB(amount);
        uint128 msb = protocol.i_calcWithdrawalAmountMSB(amount);
        uint256 res = protocol.i_mergeWithdrawalAmountParts(lsb, msb);
        assertEq(res, amount, "Amount splitting and merging failed");
    }
}
