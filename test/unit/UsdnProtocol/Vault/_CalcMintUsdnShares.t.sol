// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature The _calcMintUsdnShares internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcMintUsdnShares is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Compare calculations of USDN mint calculation with more precise
     * values when vaultBalance equal to zero
     * @custom:given An amount between 0 and `type(uint256).max`
     * @custom:and A price between 0 and `type(uint128).max/amount` or `type(uint128).max`
     * @custom:and A decimals value calculated from the protocol
     * @custom:when The mint amount is calculated
     * @custom:then The result is equal to the result of the Rust implementation
     * @param amount The amount of asset to be converted into USDN shares
     * @param price The price of the asset
     */
    function testFuzzFFI_calcMintUsdnVaultBalanceZero(uint256 amount, uint256 price) public {
        amount = bound(amount, 0, type(uint256).max);
        uint256 priceMax = type(uint256).max;
        if (amount != 0) {
            priceMax /= amount;
        }
        price = bound(price, 0, priceMax);

        uint8 assetDecimals = protocol.getAssetDecimals();
        uint8 priceFeedDecimals = protocol.getPriceFeedDecimals();
        uint8 tokensDecimals = Constants.TOKENS_DECIMALS;
        uint8 decimals = assetDecimals + priceFeedDecimals - tokensDecimals;

        bytes memory result = vmFFIRustCommand(
            "calc-mint-usdn-shares-vault-balance-zero",
            vm.toString(amount),
            vm.toString(price),
            vm.toString(decimals),
            vm.toString(usdn.divisor())
        );

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 calcRebaseTotalSupplyRust = abi.decode(result, (uint256));
        uint256 calcRebaseTotalSupplySol = usdn.convertToShares(
            FixedPointMathLib.fullMulDiv(amount, price, 10 ** (assetDecimals + priceFeedDecimals - tokensDecimals))
        );
        assertEq(
            calcRebaseTotalSupplySol,
            calcRebaseTotalSupplyRust,
            "The rust and solidity implementations should return the same value"
        );
    }

    /**
     * @custom:scenario Compare calculations of `_calcMintUsdnShares` with more precise values
     * @custom:given An amount between 0 and `type(uint256).max`
     * @custom:and A usdnTotalShares between 0 and `type(uint256).max/amount` or `type(uint256).max`
     * @custom:and A vaultBalance between 1 and `type(uint256).max`
     * @custom:when The `_calcMintUsdnShares` function is called with the value
     * @custom:then The result is equal to the result of the Rust implementation
     * @param amount The amount of asset to be converted into USDN shares
     * @param vaultBalance The balance of the vault
     * @param usdnTotalShares The total supply of USDN shares
     */
    function testFuzzFFI_calcMintUsdnShares(uint256 amount, uint256 vaultBalance, uint256 usdnTotalShares) public {
        amount = bound(amount, 0, type(uint256).max);
        uint256 usdnTotalSharesMax = type(uint256).max;
        if (amount != 0) {
            usdnTotalSharesMax /= amount;
        }
        usdnTotalShares = bound(usdnTotalShares, 0, usdnTotalSharesMax);
        vaultBalance = bound(vaultBalance, 1, type(uint256).max);

        bytes memory result = vmFFIRustCommand(
            "calc-mint-usdn-shares", vm.toString(amount), vm.toString(vaultBalance), vm.toString(usdnTotalShares)
        );

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 calcMintUsdnSharesRust = abi.decode(result, (uint256));
        uint256 calcMintUsdnSharesSol = Utils._calcMintUsdnShares(amount, vaultBalance, usdnTotalShares);
        assertEq(
            calcMintUsdnSharesSol,
            calcMintUsdnSharesRust,
            "The rust and solidity implementations should return the same value"
        );
    }

    /**
     * @custom:scenario Revert when the vault balance is zero
     * @custom:given A vault balance equal to zero
     * @custom:when The `_calcMintUsdnShares` function is called
     * @custom:then The transaction reverts with `UsdnProtocolEmptyVault`
     * forge-config: default.allow_internal_expect_revert = true
     */
    function test_RevertWhen_calcMintUsdnSharesBalanceZero() public {
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolEmptyVault.selector);
        Utils._calcMintUsdnShares(1, 0, 1);
    }
}
