// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console.sol";

/* -------------------------------------------------------------------------- */
/*                             External libraries                             */
/* -------------------------------------------------------------------------- */

/* -------------------------------- PaulRBerg ------------------------------- */

import { SD59x18 } from "@prb/math/src/SD59x18.sol";

/* ------------------------------ Open Zeppelin ----------------------------- */

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/* -------------------------------------------------------------------------- */
/*                              Internal imports                              */
/* -------------------------------------------------------------------------- */

import { TickMath } from "src/libraries/TickMath128.sol";
import { TickBitmap } from "src/libraries/TickBitmap.sol";
import { IUsdnVault, Position } from "src/interfaces/IUsdnVault.sol";
import { UsdnVaultStorage } from "./UsdnVaultStorage.sol";
import { IOracleMiddleware, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

contract UsdnVault is IUsdnVault, UsdnVaultStorage, Ownable {
    // Safe ERC20 and Tick bitmap
    using SafeERC20 for IERC20Metadata;
    using TickBitmap for mapping(int16 => uint256);

    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Constructor.
    /// @param _asset The asset ERC20 contract.
    /// @param _oracleMiddleware The oracle middleware contract.
    /// @param _tickSpacing The positions tick spacing.
    constructor(IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing)
        Ownable(msg.sender)
        UsdnVaultStorage(_asset, _oracleMiddleware, _tickSpacing)
    {
        assetDecimals = _asset.decimals();
        priceFeedDecimals = oracleMiddleware.decimals();
    }
}
