// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

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
        IUsdn usdn,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    )
        Ownable(msg.sender)
        UsdnProtocolStorage(usdn, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector)
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
            _asset.safeTransferFrom(msg.sender, address(this), depositAmount);

            emit InitiatedDeposit(msg.sender, depositAmount);
            // Mint USDN (a small amount is minted to the dead address)
            // last parameter = initializing
            currentPrice = _validateDepositWithAction(pendingAction, currentPriceData, true);
        }

        // effective liquidation tick without penalty
        int24 tickWithoutPenalty = getEffectiveTickForPrice(desiredLiqPrice); // without penalty
        // casted current price
        uint128 price = currentPrice.price.toUint128();
        // open position leverage
        uint128 leverage = _getLeverage(price, getEffectivePriceForTick(tickWithoutPenalty));
        // open position expo value
        uint256 addExpo = FixedPointMathLib.fullMulDiv(longAmount, leverage, 10 ** LEVERAGE_DECIMALS);

        {
            // verify expo is not imbalanced on long side
            _imbalanceLimitOpen(addExpo, longAmount);

            _lastUpdateTimestamp = uint40(block.timestamp);
            _lastPrice = price;

            // Transfer the wstETH for the long
            _asset.safeTransferFrom(msg.sender, address(this), longAmount);

            _createInitialPosition(msg.sender, longAmount, price, tickWithoutPenalty, leverage, addExpo);

            // // verify expo is not imbalanced on vault side
            // _imbalanceLimitDeposit(0);
        }

        _refundExcessEther();
    }

    /// @inheritdoc IUsdnProtocol
    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external onlyOwner {
        // check address zero middleware
        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolInvalidMiddlewareAddress();
        }
        _oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external onlyOwner {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        _liquidationRewardsManager = newLiquidationRewardsManager;

        emit LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /// @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        // zero minLeverage
        if (newMinLeverage <= 10 ** LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        // minLeverage greater or equal maxLeverage
        if (newMinLeverage >= _maxLeverage) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        _minLeverage = newMinLeverage;
        emit MinLeverageUpdated(newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        // maxLeverage lower or equal minLeverage
        if (newMaxLeverage <= _minLeverage) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        // maxLeverage greater than max 100
        if (newMaxLeverage > 100 * 10 ** LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        _maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        // validation deadline lower than min 1 minute
        if (newValidationDeadline < 60) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        // validation deadline greater than max 1 day
        if (newValidationDeadline > 1 days) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        _validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(newValidationDeadline);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external onlyOwner {
        // liquidationPenalty greater than max 15
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        _liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than max 2000: 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        _safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        // newLiquidationIteration greater than MAX_LIQUIDATION_ITERATION
        if (newLiquidationIteration > MAX_LIQUIDATION_ITERATION) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        _liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        // EMAPeriod is greater than max 3 months
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        _EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        // newFundingSF is greater than max
        if (newFundingSF > 10 ** FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidFundingSF();
        }

        _fundingSF = newFundingSF;
        emit FundingSFUpdated(newFundingSF);
    }

    /// @inheritdoc IUsdnProtocol
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > BPS_DIVISOR) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        _protocolFeeBps = newProtocolFeeBps;
        emit FeeBpsUpdated(newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeThreshold(uint256 newFeeThreshold) external onlyOwner {
        _feeThreshold = newFeeThreshold;
        emit FeeThresholdUpdated(newFeeThreshold);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        _feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    /// @inheritdoc IUsdnProtocol
    function setSoftLongExpoImbalanceLimit(int256 newLimit) external onlyOwner {
        if (newLimit < 0) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        } else if (newLimit > EXPO_IMBALANCE_LIMIT_DENOMINATOR) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        // TODO different lower limit
        _softLongExpoImbalanceLimit = newLimit;
    }

    /// @inheritdoc IUsdnProtocol
    function setHardLongExpoImbalanceLimit(int256 newLimit) external onlyOwner {
        if (newLimit < _softLongExpoImbalanceLimit) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        } else if (newLimit > EXPO_IMBALANCE_LIMIT_DENOMINATOR) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        // TODO different lower limit
        _hardLongExpoImbalanceLimit = newLimit;
    }

    /// @inheritdoc IUsdnProtocol
    function setSoftVaultExpoImbalanceLimit(int256 newLimit) external onlyOwner {
        if (newLimit < 0) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        } else if (newLimit > EXPO_IMBALANCE_LIMIT_DENOMINATOR) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        // TODO different lower limit
        _softVaultExpoImbalanceLimit = newLimit;
    }

    /// @inheritdoc IUsdnProtocol
    function setHardVaultExpoImbalanceLimit(int256 newLimit) external onlyOwner {
        if (newLimit < _softVaultExpoImbalanceLimit) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        } else if (newLimit > EXPO_IMBALANCE_LIMIT_DENOMINATOR) {
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        // TODO different lower limit
        _hardVaultExpoImbalanceLimit = newLimit;
    }

    /**
     * @notice Create initial open positions.
     * @param user The initial position user address.
     * @param amount The initial position amount.
     * @param price The initial position price.
     * @param tick The initial position tick.
     * @dev To be called in contract initialize.
     */
    function _createInitialPosition(
        address user,
        uint128 amount,
        uint128 price,
        int24 tick,
        uint128 leverage,
        uint256 addExpo
    ) internal {
        // apply liquidation penalty to the deployer's position
        tick = tick + int24(_liquidationPenalty) * _tickSpacing;
        Position memory long =
            Position({ user: user, amount: amount, leverage: leverage, timestamp: uint40(block.timestamp) });

        // Save the position and update the state
        (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, long, addExpo);
        emit InitiatedOpenPosition(user, long.timestamp, long.leverage, long.amount, price, tick, tickVersion, index);
        emit ValidatedOpenPosition(user, long.leverage, price, tick, tickVersion, index);
    }
}
