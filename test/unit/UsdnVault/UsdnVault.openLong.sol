// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnVault/IUsdnVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";

import "test/utils/Constants.sol";

/**
 * @custom:feature Test the long position opening of the UsdnVault
 * @custom:background Given the UsdnVault is deployed by address(this)
 */
contract UsdnVaultOpenLong is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();
        super.initialize();
    }

    /**
     * @custom:scenario Create a long position
     * @custom:when This is the first position after initialization
     * @custom:and The collateral amount is 2 ETH
     * @custom:and The liquidation price is 1000 USD
     * @custom:and The leverage is 2
     * @custom:and The ETH price is 2000 USD when the long is opened
     * @custom:and The ETH price is 2000 USD when the long is validated
     * @custom:then The liquidation price is well calculated
     * @custom:and The tick is 6910
     * @custom:and The index in the tick is 0
     * @custom:and The balance of the vault is 2 ETH
     * @custom:and The balance of the vault in short remains unchanged
     * @custom:and The balance of the vault in long is 2 ETH
     * @custom:and The total long positions is 2
     * @custom:and The long position is well stored
     * @custom:and The total exposure is 4 ETH
     * @custom:and The last price is 2000 USD
     * @custom:and The last update timestamp is now + oracle min delay
     */
    function test_openLong() external {
        // Test-specific constants
        uint256 ethPrice = 2000 ether;
        bytes memory priceData = abi.encode(uint128(ethPrice));
        uint96 collateralAmount = 2 ether;
        uint128 liquidationPrice = uint128(ethPrice) / 2; // x2 leverage
        uint256 leverage = 2;

        // Storage before
        int256 shortBalanceBefore = usdnVault.shortAssetAvailable(uint128(ethPrice))
            + usdnVault.fundingAsset(uint128(ethPrice), uint128(block.timestamp));
        int256 longBalanceBefore = usdnVault.longAssetAvailable(uint128(ethPrice))
            - usdnVault.fundingAsset(uint128(ethPrice), uint128(block.timestamp));
        uint256 totalExpoBefore = usdnVault.totalExpo();

        // Open a long position
        (int24 tick, uint256 index) = usdnVault.openLong{ value: 1 }(collateralAmount, liquidationPrice, priceData);
        // Validate the position
        usdnVault.validateLong{ value: 1 }(tick, index, priceData);

        // Check storage after
        assertEq(usdnVault.getLiquidationPrice(uint128(ethPrice), uint40(2 gwei)), ethPrice - (ethPrice / 2));
        assertEq(tick, 6910);
        assertEq(index, 0);
        assertEq(
            asset.balanceOf(address(usdnVault)),
            uint256(shortBalanceBefore + longBalanceBefore + int256(int96(collateralAmount)))
        );
        assertEq(usdnVault.balanceShort(), uint256(shortBalanceBefore));
        assertEq(usdnVault.balanceLong(), uint256(longBalanceBefore) + uint256(collateralAmount));
        assertEq(usdnVault.totalLongPositions(), 2);

        // Check position data
        Position memory long = usdnVault.getLongPosition(tick, index);
        assertEq(long.user, address(this));
        assertEq(long.amount, collateralAmount);
        assertEq(long.startPrice, uint128(ethPrice));
        assertEq(long.leverage, 2 gwei);

        assertEq(usdnVault.totalExpo(), totalExpoBefore + collateralAmount * leverage);
        assertEq(usdnVault.lastPrice(), uint128(ethPrice));
        // Block.timestamp + oracle delay => see test/unit/UsdnVault/utils/OracleMiddleware.sol
        assertEq(usdnVault.lastUpdateTimestamp(), block.timestamp + 2);
    }

    /**
     * @custom:scenario Create a long position
     * @custom:when This is the first position after initialization
     * @custom:and The collateral amount is 10 ETH
     * @custom:and The liquidation price is 1250 USD
     * @custom:and The leverage is 1.6
     * @custom:and The ETH price is 2000 USD when the long is opened
     * @custom:and The ETH price is 2050 USD when the long is validated
     * @custom:then The liquidation price is well calculated
     * @custom:and The tick is 6910
     * @custom:and The index in the tick is 0
     * @custom:and The balance of the vault is 2 ETH
     * @custom:and The balance of the vault in short remains unchanged
     * @custom:and The balance of the vault in long is 2 ETH
     * @custom:and The total long positions is 2
     * @custom:and The long position is well stored
     * @custom:and The total exposure is 4 ETH
     * @custom:and The last price is 2000 USD
     * @custom:and The last update timestamp is now + oracle min delay
     */
    function test_openLongWithLeverage() external {
        // Test-specific constants
        uint256 initialEthPrice = 2000 ether;
        uint256 finalEthPrice = 2050 ether;
        bytes memory initialPriceData = abi.encode(uint128(initialEthPrice));
        bytes memory finalPriceData = abi.encode(uint128(finalEthPrice));
        uint96 collateralAmount = 10 ether;
        uint128 liquidationPrice = uint128(initialEthPrice) / 16 * 10; // x1.6 leverage
        uint256 leverage = 1.6 ether;

        // Storage before
        int256 shortBalanceBefore = usdnVault.shortAssetAvailable(uint128(initialEthPrice))
            + usdnVault.fundingAsset(uint128(initialEthPrice), uint128(block.timestamp));
        int256 longBalanceBefore = usdnVault.longAssetAvailable(uint128(initialEthPrice))
            - usdnVault.fundingAsset(uint128(initialEthPrice), uint128(block.timestamp));
        uint256 totalExpoBefore = usdnVault.totalExpo();

        // Open a long position
        (int24 tick, uint256 index) =
            usdnVault.openLong{ value: 1 }(collateralAmount, liquidationPrice, initialPriceData);
        // Validate the position
        usdnVault.validateLong{ value: 1 }(tick, index, finalPriceData);

        // Check storage after
        assertEq(
            usdnVault.getLiquidationPrice(uint128(finalEthPrice), uint40(1.6 gwei)),
            finalEthPrice - (finalEthPrice / 16 * 10)
        );
        assertEq(tick, 7130);
        assertEq(index, 0);
        assertEq(
            asset.balanceOf(address(usdnVault)),
            uint256(shortBalanceBefore + longBalanceBefore + int256(int96(collateralAmount)))
        );
        assertEq(usdnVault.balanceShort(), uint256(shortBalanceBefore));
        assertEq(usdnVault.balanceLong(), uint256(longBalanceBefore) + uint256(collateralAmount));
        assertEq(usdnVault.totalLongPositions(), 2);

        // Check position data
        Position memory long = usdnVault.getLongPosition(tick, index);
        // assertEq(long.user, address(this));
        // assertEq(long.amount, collateralAmount);
        // assertEq(long.startPrice, uint128(finalEthPrice));
        assertEq(long.leverage, 1.6 gwei);

        // assertEq(usdnVault.totalExpo(), totalExpoBefore + collateralAmount * 16 / 10);
        // assertEq(usdnVault.lastPrice(), uint128(finalEthPrice));
        // // Block.timestamp + oracle delay => see test/unit/UsdnVault/utils/OracleMiddleware.sol
        // assertEq(usdnVault.lastUpdateTimestamp(), block.timestamp + 2);
    }
}
