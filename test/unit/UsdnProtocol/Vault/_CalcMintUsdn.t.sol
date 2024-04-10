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
     * @custom:scenario Compare calculations of `_calcMintUsdn` with more precise values
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
