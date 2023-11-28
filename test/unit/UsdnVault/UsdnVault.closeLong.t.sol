// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnVault/IUsdnVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";

import { AccessDenied } from "src/utils/Errors.sol";

import "test/utils/Constants.sol";

/**
 * @custom:feature Test the long position closing of the UsdnVault
 * @custom:background Given the UsdnVault is deployed by address(this)
 */
contract UsdnVaultCloseLong is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();
        super.initialize();
    }

    /**
     * @custom:scenario Close a long position
     * @custom:given The long to close has 2 ETH as collateral
     * @custom:and The opening ETH price is 2000 USD
     * @custom:and The liquidation price is 1000 USD
     * @custom:when The closing ETH price is 2000 USD
     * @custom:then The position is closed
     * @custom:and The user withdraw all the collaterals
     */
    function test_closeLong() external {
        /* ------------------------- Test-specific constants ------------------------ */
        uint256 ethPrice = 2000 ether;
        bytes memory priceData = abi.encode(uint128(ethPrice));
        uint96 collateral = 2 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 leverage = 2;
        uint256 initialLongDeposit = 8 ether;

        /* ---------------------- Open a long position to close --------------------- */
        (int24 tick, uint256 index) = openAndValidateLong(collateral, liquidationPrice, ethPrice);

        /* ----------------------------- /Storage before ---------------------------- */
        uint256 assetBalanceAfterLongOpening = asset.balanceOf(address(this));

        /* --------------------------------- Checks --------------------------------- */
        assertEq(usdnVault.totalExpo(), initialLongDeposit + collateral * leverage);
        assertEq(
            usdnVault.positionValue(
                uint128(ethPrice),
                uint128(ethPrice),
                uint128(collateral),
                uint40(leverage) * uint40(10 ** usdnVault.LEVERAGE_DECIMALS())
            ),
            int256(int96(collateral))
        );

        /* ------------------------- Close the long position ------------------------ */
        usdnVault.closeLong{ value: 1 }(tick, index, priceData);

        Position memory position = usdnVault.getLongPosition(tick, index);
        assertEq(position.user, address(this));
        assertEq(position.validated, false);

        usdnVault.validateLong{ value: 1 }(tick, index, priceData);

        /* --------------------------------- Checks --------------------------------- */
        assertEq(asset.balanceOf(address(this)), assetBalanceAfterLongOpening + collateral);
    }

    /**
     * @custom:scenario Close a long position
     * @custom:given The long to close has 2 ETH as collateral
     * @custom:and The opening ETH price is 2000 USD
     * @custom:and The liquidation price is 1000 USD
     * @custom:when The closing ETH price is 1500 USD
     * @custom:then The position is closed
     * @custom:and The user withdraw half the collaterals
     */
    function test_closeLongWithLoss() external {
        /* ------------------------- Test-specific constants ------------------------ */
        uint256 openingEthPrice = 2000 ether;
        uint256 closingEthPrice = 1500 ether;
        uint96 collateral = 2 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 leverage = 2;

        /* ----------------------------- Initial storage ---------------------------- */
        uint256 initialTotalExpo = usdnVault.totalExpo();

        /* ---------------------- Open a long position to close --------------------- */
        (int24 tick, uint256 index) = openAndValidateLong(collateral, liquidationPrice, openingEthPrice);

        /* ------------------------------ Storage before ---------------------------- */
        uint256 assetBalanceAfterLongOpening = asset.balanceOf(address(this));
        int256 longBalanceBefore = usdnVault.longAssetAvailable(uint128(openingEthPrice))
            - usdnVault.fundingAsset(uint128(openingEthPrice), uint128(block.timestamp));
        uint256 totalExpoAfterOpening = usdnVault.totalExpo();

        /* --------------------------------- Checks --------------------------------- */
        {
            // Prevent Stack too deep
            uint256 initialLongDeposit = 8 ether;
            assertEq(usdnVault.totalExpo(), initialLongDeposit + collateral * leverage);
        }
        assertEq(
            usdnVault.positionValue(
                uint128(openingEthPrice),
                uint128(openingEthPrice),
                uint128(collateral),
                uint40(leverage) * uint40(10 ** usdnVault.LEVERAGE_DECIMALS())
            ),
            int256(int96(collateral))
        );

        /* ------------------------- Close the long position ------------------------ */
        usdnVault.closeLong{ value: 1 }(tick, index, abi.encode(uint128(closingEthPrice)));

        Position memory position = usdnVault.getLongPosition(tick, index);

        /* --------------------------- Intermediary checks -------------------------- */
        assertEq(position.user, address(this));
        assertEq(position.validated, false);
        assertEq(usdnVault.longAssetAvailable(uint128(openingEthPrice)), longBalanceBefore);
        assertEq(usdnVault.totalExpo(), totalExpoAfterOpening);

        usdnVault.validateLong{ value: 1 }(tick, index, abi.encode(uint128(closingEthPrice)));

        /* --------------------------------- Checks --------------------------------- */
        assertEq(asset.balanceOf(address(this)), assetBalanceAfterLongOpening + collateral / 2);

        // Check vault state
        assertEq(
            usdnVault.longAssetAvailable(uint128(openingEthPrice)), longBalanceBefore - int256(uint256(collateral)) / 2
        );
        assertEq(usdnVault.totalExpo(), initialTotalExpo);
    }

    /**
     * @custom:scenario Close a long position
     * @custom:given The long to close has 2 ETH as collateral
     * @custom:and The opening ETH price is 2000 USD
     * @custom:and The liquidation price is 1000 USD
     * @custom:when The closing ETH price is 1000 USD
     * @custom:then The position is closed
     * @custom:and The user withdraw half the collaterals
     */
    function test_closeLongWithLiquidation() external {
        /* ------------------------- Test-specific constants ------------------------ */
        uint256 openingEthPrice = 2000 ether;
        uint256 closingEthPrice = 1000 ether;
        bytes memory closingEthPriceData = abi.encode(uint128(closingEthPrice));
        uint96 collateral = 2 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 leverage = 2;
        uint256 initialLongDeposit = 8 ether;

        /* ---------------------- Open a long position to close --------------------- */
        (int24 tick, uint256 index) = openAndValidateLong(collateral, liquidationPrice, openingEthPrice);

        /* ----------------------------- /Storage before ---------------------------- */
        uint256 assetBalanceAfterLongOpening = asset.balanceOf(address(this));
        int256 longBalanceBefore = usdnVault.longAssetAvailable(uint128(openingEthPrice))
            - usdnVault.fundingAsset(uint128(openingEthPrice), uint128(block.timestamp));
        uint256 totalExpoBefore = usdnVault.totalExpo();

        /* --------------------------------- Checks --------------------------------- */
        assertEq(usdnVault.totalExpo(), initialLongDeposit + collateral * leverage);
        assertEq(
            usdnVault.positionValue(
                uint128(openingEthPrice),
                uint128(openingEthPrice),
                uint128(collateral),
                uint40(leverage) * uint40(10 ** usdnVault.LEVERAGE_DECIMALS())
            ),
            int256(int96(collateral))
        );

        /* ------------------------- Close the long position ------------------------ */
        usdnVault.closeLong{ value: 1 }(tick, index, closingEthPriceData);

        Position memory position = usdnVault.getLongPosition(tick, index);

        // Check the position has been deleted
        assertEq(position.user, address(0));
        assertEq(position.amount, 0);
        assertEq(position.startPrice, 0);
        assertEq(position.leverage, 0);
        assertEq(position.validated, false);
        assertEq(position.isExit, false);
        assertEq(position.timestamp, 0);

        // Check vault state
        assertEq(usdnVault.longAssetAvailable(uint128(openingEthPrice)), longBalanceBefore);
        assertEq(usdnVault.totalExpo(), totalExpoBefore - collateral * leverage);

        // The long has been liquidated during the closeLong call
        vm.expectRevert(abi.encodeWithSelector(AccessDenied.selector));
        usdnVault.validateLong{ value: 1 }(tick, index, closingEthPriceData);

        /* --------------------------------- Checks --------------------------------- */
        assertEq(asset.balanceOf(address(this)), assetBalanceAfterLongOpening);
    }
}
