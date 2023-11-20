// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { OracleMiddleware } from "./OracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { UsdnVault } from "src/UsdnVault/UsdnVault.sol";
import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "test/utils/Constants.sol";

contract USDN is ERC20 {
    constructor() ERC20("Ultimate Synthetic Delta Neutral", "USDN") { }
}

/**
 * @title UsdnVaultFixture
 * @dev Utils for testing UsdnVault
 */
contract UsdnVaultFixture is BaseFixture {
    IUsdn usdn;
    UsdnVault usdnVault;
    OracleMiddleware oracleMiddleware;

    function setUp() public virtual {
        // TODO: replace ERC20/USDN/IUsdn by Usdn
        ERC20 _usdn = new USDN();
        usdn = IUsdn(address(_usdn));

        // Deploy a mocked oracle middleware
        oracleMiddleware = new OracleMiddleware();

        // Deploy the UsdnVault
        usdnVault = new UsdnVault(usdn, IERC20Metadata(WSTETH), oracleMiddleware, 10);

        // Open an initial position
        openAndValidateLong(10 ether, 2);

        // Assertions
        assertEq(usdn.totalSupply(), 0);
    }

    /// @notice Open a long position and validate it with 20 seconds of delay
    /// @param amount The amount of asset to deposit.
    /// @param liquidationPrice The desired liquidation price.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function openAndValidateLong(uint96 amount, uint128 liquidationPrice)
        internal
        returns (int24 tick, uint256 index)
    {
        // Compute price data
        bytes memory priceData = abi.encode(uint128(amount));
        (tick, index) = usdnVault.openLong(amount, liquidationPrice, priceData);

        // Wait 20 seconds
        vm.warp(block.timestamp + 20 seconds);

        // Validate the position
        usdnVault.validateLong(tick, index, priceData);
    }

    /// @notice Open a long position and validate it with 20 seconds of delay
    /// @param amount The amount of asset to deposit.
    /// @param leverage The desired liquidation price.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function openAndValidateLongWithLeverage(uint96 amount, uint128 leverage)
        internal
        returns (int24 tick, uint256 index)
    {
        // Compute price data
        bytes memory priceData = abi.encode(uint128(amount));
        (tick, index) = usdnVault.openLong(amount, amount - amount / leverage, priceData);

        // Wait 20 seconds
        vm.warp(block.timestamp + 20 seconds);

        // Validate the position
        usdnVault.validateLong(tick, index, priceData);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
