// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";

import { Position } from "src/interfaces/UsdnVault/IUsdnVault.sol";
import { TickMath } from "src/libraries/TickMath.sol";

import "test/utils/Constants.sol";

/**
 * @custom:feature Test the deployment and initialization of the UsdnVault
 * @custom:background Given the UsdnVault is deployed by address(this)
 */
contract UsdnVaultConcrete is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario This contract deploy the UsdnVault in the setup
     * @custom:when The underlying asset is WSTETH
     * @custom:and The tick spacing is 10 (0.1%)
     * @custom:then The USDN token is the deployed USDN contract
     * @custom:and The asset is WSTETH
     * @custom:and The asset decimals is 18
     * @custom:and The oracle middleware is the deployed OracleMiddleware contract
     * @custom:and The price feed decimals is the one of the oracle middleware
     * @custom:and The tick spacing is the one given in the setup
     */
    function test_deployment() public {
        assertEq(address(usdnVault.usdn()), address(usdn));
        assertEq(address(usdnVault.asset()), address(asset));
        assertEq(usdnVault.assetDecimals(), usdn.decimals());
        assertEq(address(usdnVault.oracleMiddleware()), address(oracleMiddleware));
        assertEq(usdnVault.priceFeedDecimals(), oracleMiddleware.decimals());
        assertEq(usdnVault.tickSpacing(), tickSpacing);
    }

    /**
     * @custom:scenario This contract initialize the UsdnVault
     * @custom:when The underlying asset is WSTETH
     * @custom:and The initial funding asset is 10 ETH
     * @custom:and The initial long asset is 8 ETH
     * @custom:and The initial price is 2000$
     * @custom:then The vault asset balance is 18 ETH
     * @custom:and The USDN total supply is 20_000 USDN
     * @custom:and The USDN balance of address(0xdead) is 20_000 USDN
     * @custom:and The vault total exposure is 8 ETH
     * @custom:and The vault long balance is 8 ETH
     * @custom:and The vault total long positions is 1
     * @custom:and The vault short balance is 10 ETH
     * @custom:and The vault last price is 2000$
     * @custom:and The vault first long position is well created
     */
    function test_initialize() public {
        // Initialize the UsdnVault
        super.initialize();

        // Test vault asset initial balance
        assertEq(asset.balanceOf(address(usdnVault)), 18 ether);

        // Test usdn balance and total supply
        assertEq(usdn.totalSupply(), 20_000 ether); // 10 ETH @ 2k$ / ETH
        assertEq(usdn.balanceOf(address(0xdead)), 20_000 ether); // 10 ETH @ 2k$ / ETH

        // Test vault state
        assertEq(usdnVault.totalExpo(), 8 ether);
        assertEq(usdnVault.balanceLong(), 8 ether);
        assertEq(usdnVault.totalLongPositions(), 1);
        assertEq(usdnVault.balanceShort(), 10 ether);
        assertEq(usdnVault.lastPrice(), 2000 ether);
        assertEq(usdnVault.lastUpdateTimestamp(), block.timestamp);
        assertEq(usdnVault.longAssetAvailable(2000 ether), 8 ether);

        // Test vault initial position
        Position memory long = usdnVault.getLongPosition(TickMath.minUsableTick(usdnVault.tickSpacing()), 0);
        assertEq(long.amount, 8 ether);
        assertEq(long.leverage, 1 gwei);
        assertEq(long.user, address(this));
        assertEq(long.startPrice, 2000 ether);
    }
}
