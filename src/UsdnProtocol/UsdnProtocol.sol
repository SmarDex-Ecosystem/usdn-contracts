// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { ProtocolAction, Position, PositionId } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolActions } from "./UsdnProtocolActions.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "../interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IRebalancer } from "../interfaces/Rebalancer/IRebalancer.sol";

contract UsdnProtocol is IUsdnProtocol, UsdnProtocolActions, Ownable2Step {
    using SafeTransferLib for address;
    using SafeCast for uint256;

    /// @inheritdoc IUsdnProtocol
    uint256 public constant MIN_INIT_DEPOSIT = 1 ether;

    /**
     * @notice Constructor
     * @param usdn The USDN ERC20 contract
     * @param sdex The SDEX ERC20 contract
     * @param asset The asset ERC20 contract (wstETH)
     * @param oracleMiddleware The oracle middleware contract
     * @param liquidationRewardsManager The liquidation rewards manager contract
     * @param tickSpacing The positions tick spacing
     * @param feeCollector The address of the fee collector
     */
    constructor(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    )
        Ownable(msg.sender)
        UsdnProtocolStorage(usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector)
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
        // since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = _usdn;
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.Initialize, block.timestamp, "", currentPriceData);

        _lastUpdateTimestamp = uint128(block.timestamp);
        _lastPrice = currentPrice.price.toUint128();

        int24 tick = getEffectiveTickForPrice(desiredLiqPrice); // without penalty
        uint128 liquidationPriceWithoutPenalty = getEffectivePriceForTick(tick);
        uint128 positionTotalExpo =
            _calcPositionTotalExpo(longAmount, currentPrice.price.toUint128(), liquidationPriceWithoutPenalty);

        _checkInitImbalance(positionTotalExpo, longAmount, depositAmount);

        _createInitialDeposit(depositAmount, currentPrice.price.toUint128());

        _createInitialPosition(longAmount, currentPrice.price.toUint128(), tick, positionTotalExpo);

        _refundEther(address(this).balance, payable(msg.sender));
    }

    /// @inheritdoc IUsdnProtocol
    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external onlyOwner {
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
    function setRebalancer(IRebalancer newRebalancer) external onlyOwner {
        _rebalancer = newRebalancer;

        emit RebalancerUpdated(address(newRebalancer));
    }

    /// @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        // zero minLeverage
        if (newMinLeverage <= 10 ** LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        if (newMinLeverage >= _maxLeverage) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        _minLeverage = newMinLeverage;
        emit MinLeverageUpdated(newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        if (newMaxLeverage <= _minLeverage) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > 100 * 10 ** LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        _maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        if (newValidationDeadline < 60) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        if (newValidationDeadline > 1 days) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        _validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(newValidationDeadline);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyOwner {
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        _liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        _safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        if (newLiquidationIteration > MAX_LIQUIDATION_ITERATION) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        _liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        _EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyOwner {
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
    function setPositionFeeBps(uint16 newPositionFee) external onlyOwner {
        // `newPositionFee` greater than 20%
        if (newPositionFee > 2000) {
            revert UsdnProtocolInvalidPositionFee();
        }
        _positionFeeBps = newPositionFee;
        emit PositionFeeUpdated(newPositionFee);
    }

    /// @inheritdoc IUsdnProtocol
    function setVaultFeeBps(uint16 newVaultFee) external onlyOwner {
        // `newVaultFee` greater than 20%
        if (newVaultFee > 2000) {
            revert UsdnProtocolInvalidVaultFee();
        }
        _vaultFeeBps = newVaultFee;
        emit VaultFeeUpdated(newVaultFee);
    }

    /// @inheritdoc IUsdnProtocol
    function setRebalancerBonusBps(uint16 newBonus) external onlyOwner {
        // `newBonus` greater than 100%
        if (newBonus > BPS_DIVISOR) {
            revert UsdnProtocolInvalidRebalancerBonus();
        }
        _rebalancerBonusBps = newBonus;
        emit RebalancerBonusUpdated(newBonus);
    }

    /// @inheritdoc IUsdnProtocol
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyOwner {
        // `newRatio` greater than 5%
        if (newRatio > SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        _sdexBurnOnDepositRatio = newRatio;

        emit BurnSdexOnDepositRatioUpdated(newRatio);
    }

    /// @inheritdoc IUsdnProtocol
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyOwner {
        _securityDepositValue = securityDepositValue;
        emit SecurityDepositValueUpdated(securityDepositValue);
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
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyOwner {
        _openExpoImbalanceLimitBps = newOpenLimitBps.toInt256();
        _depositExpoImbalanceLimitBps = newDepositLimitBps.toInt256();

        if (newWithdrawalLimitBps != 0 && newWithdrawalLimitBps < newOpenLimitBps) {
            // withdrawal limit lower than open not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        _withdrawalExpoImbalanceLimitBps = newWithdrawalLimitBps.toInt256();

        if (newCloseLimitBps != 0 && newCloseLimitBps < newDepositLimitBps) {
            // close limit lower than deposit not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        _closeExpoImbalanceLimitBps = newCloseLimitBps.toInt256();

        // casts are safe here as values are safely casted earlier
        if (
            newLongImbalanceTargetBps > int256(newCloseLimitBps)
                || newLongImbalanceTargetBps < -int256(newWithdrawalLimitBps)
                || newLongImbalanceTargetBps < -int256(BPS_DIVISOR / 2) // The target cannot be lower than -50%
        ) {
            revert UsdnProtocolInvalidLongImbalanceTarget();
        }

        _longImbalanceTargetBps = newLongImbalanceTargetBps;

        emit ImbalanceLimitsUpdated(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    /// @inheritdoc IUsdnProtocol
    function setTargetUsdnPrice(uint128 newPrice) external onlyOwner {
        if (newPrice > _usdnRebaseThreshold) {
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        if (newPrice < uint128(10 ** _priceFeedDecimals)) {
            // values smaller than $1 are not allowed
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        _targetUsdnPrice = newPrice;
        emit TargetUsdnPriceUpdated(newPrice);
    }

    /// @inheritdoc IUsdnProtocol
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyOwner {
        if (newThreshold < _targetUsdnPrice) {
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        _usdnRebaseThreshold = newThreshold;
        emit UsdnRebaseThresholdUpdated(newThreshold);
    }

    /// @inheritdoc IUsdnProtocol
    function setUsdnRebaseInterval(uint256 newInterval) external onlyOwner {
        _usdnRebaseInterval = newInterval;
        emit UsdnRebaseIntervalUpdated(newInterval);
    }

    /// @inheritdoc IUsdnProtocol
    function setMinLongPosition(uint256 newMinLongPosition) external onlyOwner {
        _minLongPosition = newMinLongPosition;
        emit MinLongPositionUpdated(newMinLongPosition);

        IRebalancer rebalancer = _rebalancer;
        if (address(rebalancer) != address(0) && rebalancer.getMinAssetDeposit() < newMinLongPosition) {
            rebalancer.setMinAssetDeposit(newMinLongPosition);
        }
    }

    /// @inheritdoc IUsdnProtocol
    function removeBlockedPendingAction(address validator, address payable to) external onlyOwner {
        uint256 pendingActionIndex = _pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        _removeBlockedPendingAction(rawIndex, to, true);
    }

    /// @inheritdoc IUsdnProtocol
    function removeBlockedPendingActionNoCleanup(address validator, address payable to) external onlyOwner {
        uint256 pendingActionIndex = _pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        _removeBlockedPendingAction(rawIndex, to, false);
    }

    /// @inheritdoc IUsdnProtocol
    function removeBlockedPendingAction(uint128 rawIndex, address payable to) external onlyOwner {
        _removeBlockedPendingAction(rawIndex, to, true);
    }

    /// @inheritdoc IUsdnProtocol
    function removeBlockedPendingActionNoCleanup(uint128 rawIndex, address payable to) external onlyOwner {
        _removeBlockedPendingAction(rawIndex, to, false);
    }

    /**
     * @notice Check if the initialize parameters lead to a balanced protocol
     * @dev This function reverts if the imbalance is exceeded for the deposit or open long action
     * @param positionTotalExpo The total expo of the deployer's long position
     * @param longAmount The amount (collateral) of the deployer's long position
     * @param depositAmount The amount of assets for the deployer's deposit
     */
    function _checkInitImbalance(uint128 positionTotalExpo, uint128 longAmount, uint128 depositAmount) internal view {
        _checkUninitialized(); // prevent using this function after initialization

        int256 longTradingExpo = _toInt256(positionTotalExpo - longAmount);
        int256 depositLimit = _depositExpoImbalanceLimitBps;
        if (depositLimit != 0) {
            int256 imbalanceBps = (_toInt256(depositAmount) - longTradingExpo) * int256(BPS_DIVISOR) / longTradingExpo;
            if (imbalanceBps > depositLimit) {
                revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }
        }
        int256 openLimit = _openExpoImbalanceLimitBps;
        if (openLimit != 0) {
            int256 imbalanceBps =
                (longTradingExpo - _toInt256(depositAmount)) * int256(BPS_DIVISOR) / _toInt256(depositAmount);
            if (imbalanceBps > openLimit) {
                revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }
        }
    }

    /**
     * @notice Create initial deposit
     * @dev To be called from `initialize`
     * @param amount The initial deposit amount
     * @param price The current asset price
     */
    function _createInitialDeposit(uint128 amount, uint128 price) internal {
        _checkUninitialized(); // prevent using this function after initialization

        // transfer the wstETH for the deposit
        address(_asset).safeTransferFrom(msg.sender, address(this), amount);
        _balanceVault += amount;
        emit InitiatedDeposit(msg.sender, msg.sender, amount, block.timestamp);

        // calculate the total minted amount of USDN shares (vault balance and total supply are zero for now, we assume
        // the USDN price to be $1 per token)
        uint256 usdnSharesToMint = _calcMintUsdnShares(amount, 0, 0, price);
        uint256 minUsdnSharesSupply = _usdn.convertToShares(MIN_USDN_SUPPLY);
        // mint the minimum amount and send it to the dead address so it can never be removed from the total supply
        _usdn.mintShares(DEAD_ADDRESS, minUsdnSharesSupply);
        // mint the user's share
        uint256 mintSharesToUser = usdnSharesToMint - minUsdnSharesSupply;
        uint256 mintedTokens = _usdn.mintShares(msg.sender, mintSharesToUser);

        // emit events
        emit ValidatedDeposit(DEAD_ADDRESS, DEAD_ADDRESS, 0, MIN_USDN_SUPPLY, block.timestamp);
        emit ValidatedDeposit(msg.sender, msg.sender, amount, mintedTokens, block.timestamp);
    }

    /**
     * @notice Create initial long position
     * @dev To be called from `initialize`
     * @param amount The initial position amount
     * @param price The current asset price
     * @param tick The tick corresponding to the liquidation price (without penalty)
     * @param totalExpo The total expo of the position
     */
    function _createInitialPosition(uint128 amount, uint128 price, int24 tick, uint128 totalExpo) internal {
        _checkUninitialized(); // prevent using this function after initialization

        // transfer the wstETH for the long
        address(_asset).safeTransferFrom(msg.sender, address(this), amount);

        // apply liquidation penalty to the deployer's liquidationPriceWithoutPenalty
        uint8 liquidationPenalty = _liquidationPenalty;
        PositionId memory posId;
        posId.tick = tick + int24(uint24(liquidationPenalty)) * _tickSpacing;
        Position memory long = Position({
            validated: true,
            user: msg.sender,
            amount: amount,
            totalExpo: totalExpo,
            timestamp: uint40(block.timestamp)
        });
        // save the position and update the state
        (posId.tickVersion, posId.index,) = _saveNewPosition(posId.tick, long, liquidationPenalty);
        _balanceLong += long.amount;
        emit InitiatedOpenPosition(msg.sender, msg.sender, long.timestamp, totalExpo, long.amount, price, posId);
        emit ValidatedOpenPosition(msg.sender, msg.sender, totalExpo, price, posId);
    }
}
