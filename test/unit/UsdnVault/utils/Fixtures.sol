// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";
import { OracleMiddleware } from "test/unit/UsdnVault/utils/OracleMiddleware.sol";
import "test/utils/Constants.sol";

import { IUsdn } from "src/interfaces/IUsdn.sol";
import { UsdnVault } from "src/UsdnVault/UsdnVault.sol";

// TODO: Use the real USDN contract instead of this mock
contract USDN is ERC20 {
    constructor() ERC20("Ultimate Synthetic Delta Neutral", "USDN") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title UsdnVaultFixture
 * @dev Utils for testing UsdnVault
 */
contract UsdnVaultFixture is BaseFixture {
    IUsdn usdn;
    IERC20Metadata asset;
    UsdnVault usdnVault;
    OracleMiddleware oracleMiddleware;
    int24 tickSpacing = 10;

    function setUp() public virtual forkEthereum {
        // TODO: replace ERC20/USDN/IUsdn by Usdn
        ERC20 _usdn = new USDN();
        usdn = IUsdn(address(_usdn));

        // Deploy a mocked oracle middleware
        oracleMiddleware = new OracleMiddleware();

        // Deploy the UsdnVault
        asset = IERC20Metadata(WSTETH);
        usdnVault = new UsdnVault(usdn, asset, oracleMiddleware, tickSpacing);
    }

    function initialize() internal {
        // Initialize UsdnVault
        deal(WSTETH, address(this), 10_000 ether);
        asset.approve(address(usdnVault), type(uint256).max);
        usdnVault.initialize(10 ether, 8 ether, 2000 ether);
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
        bytes memory priceData = abi.encode(uint128(2000 ether));
        (tick, index) = usdnVault.openLong{ value: 1 }(amount, liquidationPrice, priceData);

        // Wait 20 seconds
        vm.warp(block.timestamp + 20 seconds);

        // Validate the position
        usdnVault.validateLong{ value: 1 }(tick, index, priceData);
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
        (tick, index) = openAndValidateLong(amount, amount - amount / leverage);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
