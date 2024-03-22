// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { ProtocolAction, Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { UsdnProtocolActions } from "src/UsdnProtocol/UsdnProtocolActions.sol";
import { IUsdnProtocolParams } from "src/interfaces/UsdnProtocol/IUsdnProtocolParams.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

contract UsdnProtocol is IUsdnProtocol, UsdnProtocolActions, Ownable {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;

    /// @inheritdoc IUsdnProtocol
    uint256 public constant MIN_INIT_DEPOSIT = 1 ether;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param tickSpacing The positions tick spacing.
     * @param feeCollector The address of the fee collector.
     */
    constructor(
        IUsdnProtocolParams params,
        IUsdn usdn,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    )
        Ownable(msg.sender)
        UsdnProtocolStorage(params, usdn, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector)
    { }

    /// @inheritdoc IUsdnProtocol
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable initializer {
        if (depositAmount < MIN_INIT_DEPOSIT) {
            revert UsdnProtocolMinInitAmount(MIN_INIT_DEPOSIT);
        }
        if (longAmount < MIN_INIT_DEPOSIT) {
            revert UsdnProtocolMinInitAmount(MIN_INIT_DEPOSIT);
        }
        // Since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = _usdn;
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }

        PriceInfo memory currentPrice = _getOraclePrice(ProtocolAction.Initialize, block.timestamp, currentPriceData);

        // Create vault deposit
        _createInitialDeposit(depositAmount, currentPrice.price.toUint128());

        _lastUpdateTimestamp = uint128(block.timestamp);
        _lastPrice = currentPrice.price.toUint128();

        int24 tick = getEffectiveTickForPrice(desiredLiqPrice); // without penalty
        uint128 liquidationPriceWithoutPenalty = getEffectivePriceForTick(tick);
        uint128 leverage = _getLeverage(currentPrice.price.toUint128(), liquidationPriceWithoutPenalty);
        uint128 positionTotalExpo =
            _calculatePositionTotalExpo(longAmount, currentPrice.price.toUint128(), liquidationPriceWithoutPenalty);

        // verify expo is not imbalanced on long side
        _checkImbalanceLimitOpen(positionTotalExpo, longAmount);

        // Create long position
        _createInitialPosition(longAmount, currentPrice.price.toUint128(), tick, leverage, positionTotalExpo);

        _refundExcessEther();
    }

    /**
     * @notice Create initial deposit
     * @dev To be called from `initialize`
     * @param amount The initial deposit amount
     * @param price The current asset price
     */
    function _createInitialDeposit(uint128 amount, uint128 price) internal {
        _checkUninitialized(); // prevent using this function after initialization

        // Transfer the wstETH for the deposit
        _asset.safeTransferFrom(msg.sender, address(this), amount);
        _balanceVault += amount;
        emit InitiatedDeposit(msg.sender, amount, block.timestamp);

        // Calculate the total minted amount of USDN (vault balance and total supply are zero for now, we assume the
        // USDN price to be $1)
        uint256 usdnToMint = _calcMintUsdn(amount, 0, 0, price);
        // Mint the min amount and send to dead address so it can never be removed from the total supply
        _usdn.mint(DEAD_ADDRESS, MIN_USDN_SUPPLY);
        // Mint the user's share
        uint256 mintToUser = usdnToMint - MIN_USDN_SUPPLY;
        _usdn.mint(msg.sender, mintToUser);

        // Emit events
        emit ValidatedDeposit(DEAD_ADDRESS, 0, MIN_USDN_SUPPLY, block.timestamp);
        emit ValidatedDeposit(msg.sender, amount, mintToUser, block.timestamp);
    }

    /**
     * @notice Create initial long position
     * @dev To be called from `initialize`
     * @param amount The initial position amount
     * @param price The current asset price
     * @param tick The tick corresponding to the liquidation price (without penalty)
     */
    function _createInitialPosition(
        uint128 amount,
        uint128 price,
        int24 tick,
        uint128 leverage,
        uint128 positionTotalExpo
    ) internal {
        _checkUninitialized(); // prevent using this function after initialization

        // Transfer the wstETH for the long
        _asset.safeTransferFrom(msg.sender, address(this), amount);

        // apply liquidation penalty to the deployer's liquidationPriceWithoutPenalty
        tick = tick + int24(_params.getLiquidationPenalty()) * _tickSpacing;
        Position memory long = Position({
            user: msg.sender,
            amount: amount,
            totalExpo: positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        // Save the position and update the state
        (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, long);
        emit InitiatedOpenPosition(msg.sender, long.timestamp, leverage, long.amount, price, tick, tickVersion, index);
        emit ValidatedOpenPosition(msg.sender, leverage, price, tick, tickVersion, index);
    }
}
