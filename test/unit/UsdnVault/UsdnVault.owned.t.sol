// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { OracleMiddleware } from "test/unit/UsdnVault/utils/OracleMiddleware.sol";
import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";
import "test/utils/Constants.sol";

/**
 * @custom:feature Test the onlyOwner features of the UsdnVault
 * @custom:background Given the owner is address(this)
 */
contract UsdnVaultOwnedFeatures is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario The owner set the funding rate
     * @custom:when The funding rate is set to 10000000
     * @custom:then The funding rate is 10000000
     */
    function test_setFundingRate() public {
        int256 _newFundingRate = 10_000_000;
        usdnVault.setFundingRate(_newFundingRate);

        assertEq(usdnVault.fundingRatePerSecond(), _newFundingRate);
    }

    /**
     * @custom:scenario The owner set the min and max leverage
     * @custom:when The min leverage is set to 2 gwei
     * @custom:and The max leverage is set to 10 gwei
     * @custom:then The min leverage is 2 gwei
     * @custom:and The max leverage is 10 gwei
     */
    function test_setMinMaxLeverage() public {
        uint256 _minLeverage = 2 gwei;
        uint256 _maxLeverage = 10 gwei;
        usdnVault.setMinMaxLeverage(_minLeverage, _maxLeverage);

        assertEq(usdnVault.minLeverage(), _minLeverage);
        assertEq(usdnVault.maxLeverage(), _maxLeverage);
    }

    /**
     * @custom:scenario The owner set the oracle middleware
     * @custom:when The oracle middleware is set to a new OracleMiddleware contract
     * @custom:then The oracle middleware is the new OracleMiddleware contract address
     */
    function test_setOracleMiddleware() public {
        // Deploy a mocked oracle middleware
        address _newOracleMiddleware = address(new OracleMiddleware());
        usdnVault.setOracleMiddleware(_newOracleMiddleware);

        assertEq(address(usdnVault.oracleMiddleware()), _newOracleMiddleware);
    }
}
