// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The _calcRebaseTotalSupply internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolCalcRebaseTotalSupply is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Compare calculations of `_calcRebaseTotalSupply` with more precise values
     */
    function testFuzzFFI_calcRebaseTotalSupply(
        uint256 vaultBalance,
        uint128 assetPrice,
        uint128 targetPrice,
        uint8 assetDecimals
    ) public {
        vaultBalance = bound(vaultBalance, 1, type(uint256).max);
        assetPrice = uint128(bound(assetPrice, 1, type(uint128).max));
        targetPrice = uint128(bound(targetPrice, 1, type(uint128).max));
        assetDecimals = uint8(bound(assetDecimals, 1, type(uint8).max));

        bytes memory result = vmFFIRustCommand(
            "calc-rebase-total-supply",
            vm.toString(vaultBalance),
            vm.toString(assetPrice),
            vm.toString(targetPrice),
            vm.toString(assetDecimals)
        );

        // Sanity check
        require(keccak256(result) != keccak256(""), "Rust implementation returned an error");

        uint256 calcRebaseTotalSupplyRust = abi.decode(result, (uint256));
        uint256 calcRebaseTotalSupplySol =
            protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        assertEq(
            calcRebaseTotalSupplySol,
            calcRebaseTotalSupplyRust,
            "The rust and solidity implementations should return the same value"
        );
    }
}
