// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnVaultHandler } from "test/unit/UsdnVault/utils/Handler.sol";
import { OracleMiddleware } from "test/unit/UsdnVault/utils/OracleMiddleware.sol";
import "test/utils/Constants.sol";

import { IUsdn } from "src/interfaces/IUsdn.sol";
import { UsdnVault } from "src/UsdnVault/UsdnVault.sol";

import { console2 } from "forge-std/Test.sol";

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
    UsdnVaultHandler usdnVault;
    OracleMiddleware oracleMiddleware;
    int24 tickSpacing = 10;

    function setUp() public virtual {
        copyAssetCode(WSTETH);

        // TODO: replace ERC20/USDN/IUsdn by Usdn
        ERC20 _usdn = new USDN();
        usdn = IUsdn(address(_usdn));

        // Deploy a mocked oracle middleware
        oracleMiddleware = new OracleMiddleware();

        // Deploy the UsdnVault
        asset = IERC20Metadata(WSTETH);

        address[] memory _actors = new address[](4);
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;

        usdnVault = new UsdnVaultHandler(usdn, asset, oracleMiddleware, tickSpacing, _actors);
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
    /// @param ethPrice The ETH price used for opening and validation.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function openAndValidateLong(uint96 amount, uint128 liquidationPrice, uint256 ethPrice)
        internal
        returns (int24, uint256)
    {
        return openAndValidateLong(amount, liquidationPrice, ethPrice, ethPrice);
    }

    /// @notice Open a long position and validate it with 20 seconds of delay
    /// @param amount The amount of asset to deposit.
    /// @param liquidationPrice The desired liquidation price.
    /// @param openingEthPrice The ETH price used for opening.
    /// @param validatedEthPrice The ETH price used for validation.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function openAndValidateLong(
        uint96 amount,
        uint128 liquidationPrice,
        uint256 openingEthPrice,
        uint256 validatedEthPrice
    ) internal returns (int24 tick, uint256 index) {
        // Compute prices data
        bytes memory openingPriceData = abi.encode(uint128(openingEthPrice));
        bytes memory validatedPriceData = abi.encode(uint128(validatedEthPrice));

        // Open a long position
        (tick, index) = usdnVault.openLong{ value: 1 }(amount, liquidationPrice, openingPriceData);

        // Wait 20 seconds
        vm.warp(block.timestamp + 20 seconds);

        // Validate the position
        usdnVault.validateLong{ value: 1 }(tick, index, validatedPriceData);
    }

    function copyAssetCode(address _asset) internal {
        string[] memory cmds = new string[](5);
        cmds[0] = "cast";
        cmds[1] = "code";
        cmds[2] = "--rpc-url";
        cmds[3] = vm.envString("URL_ETH_MAINNET");
        cmds[4] = vm.toString(_asset);
        bytes memory assetBytecode = vm.ffi(cmds);

        vm.etch(_asset, assetBytecode);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
