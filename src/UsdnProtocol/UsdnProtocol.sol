// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import {
    PendingAction,
    VaultPendingAction,
    ProtocolAction,
    Position
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { UsdnProtocolActions } from "src/UsdnProtocol/UsdnProtocolActions.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

contract UsdnProtocol is IUsdnProtocol, UsdnProtocolActions, Ownable {
    using SafeCast for uint256;

    /// @dev The minimum amount of wstETH for the initialization deposit and long.
    uint256 public constant MIN_INIT_DEPOSIT = 1 ether;

    /// @dev The amount of collateral for the first "dead" long position.
    uint128 public constant FIRST_LONG_AMOUNT = 1000;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param tickSpacing The positions tick spacing.
     */
    constructor(
        IUsdn usdn,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing
    ) Ownable(msg.sender) UsdnProtocolStorage(usdn, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing) { }

    /**
     * @notice Initialize the protocol.
     * @dev This function can only be called once. Other external functions can only be called after the initialization.
     * @param depositAmount The amount of wstETH to deposit.
     * @param longAmount The amount of wstETH to use for the long.
     * @param desiredLiqPrice The desired liquidation price for the long.
     * @param currentPriceData The current price data.
     */
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

        // Create vault deposit
        PriceInfo memory currentPrice;
        {
            PendingAction memory pendingAction = _convertVaultPendingAction(
                VaultPendingAction({
                    action: ProtocolAction.ValidateDeposit,
                    timestamp: 0, // not needed since we have a special ProtocolAction for init
                    user: msg.sender,
                    _unused: 0, // unused
                    amount: depositAmount,
                    assetPrice: 0, // special case for init
                    totalExpo: 0,
                    balanceVault: 0,
                    balanceLong: 0,
                    usdnTotalSupply: 0
                })
            );

            // Transfer the wstETH for the deposit
            _retrieveAssetsAndCheckBalance(msg.sender, depositAmount);

            emit InitiatedDeposit(msg.sender, depositAmount);
            // Mint USDN (a small amount is minted to the dead address)
            // last parameter = initializing
            currentPrice = _validateDepositWithAction(pendingAction, currentPriceData, true);
        }

        _lastUpdateTimestamp = uint40(block.timestamp);
        _lastPrice = currentPrice.price.toUint128();

        // Transfer the wstETH for the long
        _retrieveAssetsAndCheckBalance(msg.sender, longAmount);

        // Create long positions with min leverage
        _createInitialPosition(DEAD_ADDRESS, FIRST_LONG_AMOUNT, currentPrice.price.toUint128(), minTick());
        _createInitialPosition(
            msg.sender,
            longAmount - FIRST_LONG_AMOUNT,
            currentPrice.price.toUint128(),
            getEffectiveTickForPrice(desiredLiqPrice) // no liquidation penalty
        );
    }

    function _createInitialPosition(address user, uint128 amount, uint128 price, int24 tick) internal {
        uint128 liquidationPrice = getEffectivePriceForTick(tick);
        uint128 leverage = _getLeverage(price, liquidationPrice);
        Position memory long = Position({
            user: user,
            amount: amount,
            startPrice: price,
            leverage: leverage,
            timestamp: uint40(block.timestamp)
        });
        // Save the position and update the state
        (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, long);
        emit InitiatedOpenPosition(user, long, tick, tickVersion, index);
        emit ValidatedOpenPosition(user, long, tick, tickVersion, index, liquidationPrice);
    }

    /**
     * @notice Replace the LiquidationRewardsManager contract with a new implementation.
     * @dev Cannot be the 0 address.
     * @param newLiquidationRewardsManager the address of the new contract.
     */
    function setLiquidationRewardsManager(address newLiquidationRewardsManager) external onlyOwner {
        if (newLiquidationRewardsManager == address(0)) {
            revert UsdnProtocolLiquidationRewardsManagerIsZeroAddress();
        }

        _liquidationRewardsManager = ILiquidationRewardsManager(newLiquidationRewardsManager);

        emit LiquidationRewardsManagerUpdated(newLiquidationRewardsManager);
    }
}
