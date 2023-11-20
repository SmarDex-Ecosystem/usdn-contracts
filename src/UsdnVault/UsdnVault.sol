// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             External libraries                             */
/* -------------------------------------------------------------------------- */

/* ------------------------------ Open Zeppelin ----------------------------- */

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/* -------------------------------------------------------------------------- */
/*                              Internal imports                              */
/* -------------------------------------------------------------------------- */

import { TickMath } from "src/libraries/TickMath.sol";
import { TickBitmap } from "src/libraries/TickBitmap.sol";
import { IUsdnVault, Position } from "src/interfaces/UsdnVault/IUsdnVault.sol";
import { UsdnVaultPerps } from "./UsdnVaultPerps.sol";
import { IOracleMiddleware, PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";

import {
    ZeroAmount,
    IncompleteTransfer,
    InvalidOracleMiddleware,
    FundingRateInvalid,
    MinLeverageInvalid,
    MaxLeverageInvalid
} from "../utils/Errors.sol";

contract UsdnVault is IUsdnVault, UsdnVaultPerps, Ownable, Initializable {
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
    constructor(IUsdn _usdn, IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing)
        Ownable(msg.sender)
        UsdnVaultPerps(_usdn, _asset, _oracleMiddleware, _tickSpacing)
    { }

    /// @notice Initialize the vault.
    /// @dev To be called once the vault is authorized to transfer the asset.
    function initialize(uint256 _depositShort, uint96 _depositLong, uint128 _currentPrice)
        external
        initializer
        onlyOwner
    {
        if (_depositShort == 0) revert ZeroAmount();
        if (_depositLong == 0) revert ZeroAmount();

        balanceShort += _depositShort;
        balanceLong += _depositLong;

        // Leverage x1
        totalExpo += _depositLong;

        lastPrice = _currentPrice;
        lastUpdateTimestamp = uint128(block.timestamp);

        {
            uint256 usdnToMint = _calcMintUsdp(_depositShort, _currentPrice);

            // Initialize default positions
            Position memory initialLong = Position({
                user: msg.sender,
                amount: _depositLong,
                startPrice: _currentPrice,
                leverage: 1 gwei,
                validated: true,
                isExit: false,
                timestamp: uint40(block.timestamp)
            });
            int24 tick = TickMath.minUsableTick(tickSpacing); // leverage 1 = liquidation price 0 => use lowest tick
            Position[] storage pos = longPositions[_tickHash(tick)];
            pos.push(initialLong);

            bytes32 tickHash = _tickHash(tick);
            totalExpoByTick[tickHash] += _depositLong; // leverage 1x
            ++positionsInTick[tickHash];

            totalLongPositions += 1;
            tickBitmap.flipTick(tick, tickSpacing);
            maxInitializedTick = tick;

            usdn.mint(address(0xdead), usdnToMint);
        }

        uint256 balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), _depositShort + _depositLong);

        if (asset.balanceOf(address(this)) != balanceBefore + _depositShort + _depositLong) {
            revert IncompleteTransfer(asset.balanceOf(address(this)), balanceBefore + _depositShort + _depositLong);
        }
    }

    /// @notice Manually set the funding rate.
    /// @param _fundingRatePerSecond The new funding rate.
    function setFundingRate(int256 _fundingRatePerSecond) external onlyOwner {
        if (_fundingRatePerSecond <= 0) revert FundingRateInvalid();
        if (_fundingRatePerSecond > 11_574_074_074) revert FundingRateInvalid(); // 0.1% daily max
        fundingRatePerSecond = _fundingRatePerSecond;
    }

    /// @notice Set the min and max leverage.
    /// @param _minLeverage The new min leverage.
    /// @param _maxLeverage The new max leverage.
    function setMinMaxLeverage(uint256 _minLeverage, uint256 _maxLeverage) external onlyOwner {
        if (_minLeverage <= 1 * 10 ** LEVERAGE_DECIMALS + 1) {
            revert MinLeverageInvalid();
        }
        if (_maxLeverage <= 1 * 10 ** LEVERAGE_DECIMALS + 1) {
            revert MaxLeverageInvalid();
        }
        if (_maxLeverage > 20 * 10 ** LEVERAGE_DECIMALS) {
            revert MaxLeverageInvalid();
        }
        if (_minLeverage > _maxLeverage) revert MinLeverageInvalid();
        minLeverage = _minLeverage;
        maxLeverage = _maxLeverage;
    }

    /// @notice Set the oracle middleware address.
    /// @param _oracleMiddleware The new oracle middleware address.
    function setOracleMiddleware(address _oracleMiddleware) external onlyOwner {
        if (_oracleMiddleware.code.length == 0) revert InvalidOracleMiddleware();
        oracleMiddleware = IOracleMiddleware(_oracleMiddleware);
    }
}
