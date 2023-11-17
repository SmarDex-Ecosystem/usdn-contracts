// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";

/// Deterministic tests, general conversions
contract UsdnVaultConcrete is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();
    }
}
