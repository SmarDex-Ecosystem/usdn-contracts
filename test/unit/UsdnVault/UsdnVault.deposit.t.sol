// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnVault/IUsdnVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";

import "test/utils/Constants.sol";

/**
 * @custom:feature Test the short position opening of the UsdnVault
 * @custom:background Given the UsdnVault is deployed by address(this)
 */
contract UsdnVaultDeposit is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();
        super.initialize();
    }

    /**
     * @custom:scenario Deposit asset in the vault
     * @custom:when The amount of asset is 1 ether
     * @custom:and The price of the ETH is 2000 ether and does not change
     * @custom:then The price
     */
    function test_deposit() external {
        /* ------------------------- Test-specific constants ------------------------ */
        uint256 ethPrice = 2000 ether;
        uint256 depositAmount = 1 ether;

        /* ----------------------------- Storage before ----------------------------- */
        int256 shortBalanceBefore = usdnVault.shortAssetAvailable(uint128(ethPrice))
            + usdnVault.fundingAsset(uint128(ethPrice), uint128(block.timestamp));
        int256 longBalanceBefore = usdnVault.longAssetAvailable(uint128(ethPrice))
            - usdnVault.fundingAsset(uint128(ethPrice), uint128(block.timestamp));

        /* --------------------------------- Deposit -------------------------------- */
        usdnVault.deposit{ value: 1 }(uint128(depositAmount), abi.encode(uint128(ethPrice)));

        /* --------------------------------- Checks --------------------------------- */
        assertEq(
            asset.balanceOf(address(usdnVault)),
            uint256(uint256(shortBalanceBefore) + uint256(longBalanceBefore)) + depositAmount,
            "Vault asset balance after deposit"
        );
        assertEq(usdnVault.balanceShort(), uint256(shortBalanceBefore), "Vault Short balance after deposit");
        assertEq(usdnVault.balanceLong(), uint256(longBalanceBefore), "Vault Long balance after deposit");
        assertEq(usdnVault.usdn().balanceOf(address(this)), 0, "Vault USDN balance after deposit");
        assertEq(
            usdnVault.usdn().totalSupply(),
            usdnVault.usdn().balanceOf(address(0xdead)),
            "Vault USDN total supply after deposit"
        );

        // Advance time
        vm.warp(block.timestamp + 20 seconds);

        /* ----------------------------- Validate short ----------------------------- */
        usdnVault.validateShort{ value: 1 }(abi.encode(uint128(uint128(ethPrice))));

        /* --------------------------------- Checks --------------------------------- */
        assertEq(
            asset.balanceOf(address(usdnVault)),
            uint256(uint256(shortBalanceBefore) + uint256(longBalanceBefore) + depositAmount),
            "Vault asset balance after validation"
        );
        assertEq(
            usdnVault.balanceShort(),
            uint256(shortBalanceBefore) + depositAmount,
            "Vault Short balance after validation"
        );
        assertEq(usdnVault.balanceLong(), uint256(longBalanceBefore), "Vault Long balance after validation");

        assertEq(usdnVault.usdn().balanceOf(address(this)), uint128(ethPrice), "Vault USDN balance after validation");
        assertEq(
            usdnVault.usdn().totalSupply(),
            usdnVault.usdn().balanceOf(address(this)) + usdnVault.usdn().balanceOf(address(0xdead)),
            "Vault USDN total supply after validation"
        );

        assertEq(usdnVault.lastPrice(), uint128(ethPrice), "Vault last price after validation");
        assertEq(usdnVault.lastUpdateTimestamp(), block.timestamp, "Vault last update timestamp after validation");
    }
}
