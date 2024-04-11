// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The _calcMintUsdn internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcMintUsdn is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Compare calculations of `_calcMintUsdn` with more precise
     * values and vaultBalance equal to zero
     * @custom:given A amount between 1 and `type(uint128).max`
     * @custom:and A price between 1 and `type(uint128).max`
     * @custom:and A decimals value calculated from the protocol
     * @custom:when The `_calcMintUsdn` function is called with the value
     * @custom:then The result is equal to the result of the Rust implementation
     * @param amount The amount of asset to be converted into USDN
     * @param price The price of the asset (only used for initialization)
     */
    function testFuzzFFI_calcMintUsdnVaultBalanceZero(uint256 amount, uint256 price) public {
        amount = bound(amount, 1, type(uint128).max);
        price = bound(price, 1, type(uint128).max);
        uint8 assetDecimals = protocol.getAssetDecimals();
        uint8 priceFeedDecimals = protocol.getPriceFeedDecimals();
        uint8 tokensDecimals = protocol.TOKENS_DECIMALS();
        uint8 decimals = assetDecimals + priceFeedDecimals - tokensDecimals;

        bytes memory result = vmFFIRustCommand(
            "calc-mint-usdn-vault-balance-zero", vm.toString(amount), vm.toString(price), vm.toString(decimals)
        );

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 calcRebaseTotalSupplyRust = abi.decode(result, (uint256));
        uint256 calcRebaseTotalSupplySol = protocol.i_calcMintUsdn(amount, 0, 0, price);
        assertEq(
            calcRebaseTotalSupplySol,
            calcRebaseTotalSupplyRust,
            "The rust and solidity implementations should return the same value"
        );
    }

    /**
     * @custom:scenario Compare calculations of `_calcMintUsdn` with more precise values
     * @custom:given A amount between 1 and `type(uint128).max`
     * @custom:and A vaultBalance between 1 and `type(uint128).max`
     * @custom:and A usdnTotalSupply between 1 and `type(uint128).max`
     * @custom:when The `_calcMintUsdn` function is called with the value
     * @custom:then The result is equal to the result of the Rust implementation
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault (not used for initialization)
     * @param usdnTotalSupply The total supply of USDN (not used for initialization)
     */
    function testFuzzFFI_calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply) public {
        amount = bound(amount, 1, type(uint128).max);
        vaultBalance = bound(vaultBalance, 1, type(uint128).max);
        usdnTotalSupply = bound(usdnTotalSupply, 1, type(uint128).max);

        bytes memory result = vmFFIRustCommand(
            "calc-mint-usdn", vm.toString(amount), vm.toString(vaultBalance), vm.toString(usdnTotalSupply)
        );

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 calcRebaseTotalSupplyRust = abi.decode(result, (uint256));
        uint256 calcRebaseTotalSupplySol = protocol.i_calcMintUsdn(amount, vaultBalance, usdnTotalSupply, 1);
        assertEq(
            calcRebaseTotalSupplySol,
            calcRebaseTotalSupplyRust,
            "The rust and solidity implementations should return the same value"
        );
    }
}
