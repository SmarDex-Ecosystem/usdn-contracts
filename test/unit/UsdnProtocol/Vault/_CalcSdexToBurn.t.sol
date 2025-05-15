// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

/**
 * @custom:feature The _calcSdexToBurn internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcUsdnPrice is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the calculation of the amount of SDEX tokens to burn depending on the amount of USDN
     * @custom:given An amount of USDN to be minted
     * @custom:when The function is called with this amount
     * @custom:then The correct amount of SDEX to burn is returned
     */
    function test_calcSdexToBurn() public view {
        uint64 burnRatio = protocol.getSdexBurnOnDepositRatio();
        uint256 burnRatioDivisor = Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR;
        uint8 usdnDecimals = Constants.TOKENS_DECIMALS;

        uint256 usdnToMint = 100 * 10 ** usdnDecimals;
        uint256 expectedSdexToBurn = usdnToMint * burnRatio / burnRatioDivisor;
        uint256 sdexToBurn = protocol.i_calcSdexToBurn(usdnToMint, burnRatio);
        assertEq(sdexToBurn, expectedSdexToBurn, "Result does not match the expected value");

        usdnToMint = 1_582_309 * 10 ** (usdnDecimals - 2);
        expectedSdexToBurn = usdnToMint * burnRatio / burnRatioDivisor;
        sdexToBurn = protocol.i_calcSdexToBurn(usdnToMint, burnRatio);
        assertEq(
            sdexToBurn,
            expectedSdexToBurn,
            "Result does not match expected value when the usdn to mint value is less round"
        );
    }
}
