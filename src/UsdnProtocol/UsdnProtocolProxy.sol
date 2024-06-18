// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ProtocolAction } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolEvents } from "../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolActionsEntry } from "./UsdnProtocolActionsEntry.sol";
import { UsdnProtocolCoreEntry } from "./UsdnProtocolCoreEntry.sol";
import { UsdnProtocolLongEntry } from "./UsdnProtocolLongEntry.sol";
import { UsdnProtocolVaultEntry } from "./UsdnProtocolVaultEntry.sol";
import { UsdnProtocolActionsLibrary as actionsLib } from "./UsdnProtocolActionsLibrary.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "./UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "./UsdnProtocolLongLibrary.sol";

contract UsdnProtocol is
    UsdnProtocolLongEntry,
    UsdnProtocolVaultEntry,
    UsdnProtocolCoreEntry,
    UsdnProtocolActionsEntry,
    IUsdnProtocolEvents
{
    using SafeTransferLib for address;
    using SafeCast for uint256;

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
        IBaseOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    )
        UsdnProtocolBaseStorage(usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector)
    { }

    // / @inheritdoc IUsdnProtocol
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable {
        if (depositAmount < s.MIN_INIT_DEPOSIT) {
            revert UsdnProtocolMinInitAmount(s.MIN_INIT_DEPOSIT);
        }
        if (longAmount < s.MIN_INIT_DEPOSIT) {
            revert UsdnProtocolMinInitAmount(s.MIN_INIT_DEPOSIT);
        }
        // since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = s._usdn;
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }

        PriceInfo memory currentPrice =
            actionsLib._getOraclePrice(s, ProtocolAction.Initialize, block.timestamp, "", currentPriceData);

        s._lastUpdateTimestamp = uint128(block.timestamp);
        s._lastPrice = currentPrice.price.toUint128();

        int24 tick = getEffectiveTickForPrice(desiredLiqPrice); // without penalty
        uint128 liquidationPriceWithoutPenalty = getEffectivePriceForTick(tick);
        uint128 positionTotalExpo =
            longLib._calcPositionTotalExpo(longAmount, currentPrice.price.toUint128(), liquidationPriceWithoutPenalty);

        vaultLib._checkInitImbalance(s, positionTotalExpo, longAmount, depositAmount);

        vaultLib._createInitialDeposit(s, depositAmount, currentPrice.price.toUint128());

        vaultLib._createInitialPosition(s, longAmount, currentPrice.price.toUint128(), tick, positionTotalExpo);

        actionsLib._refundEther(address(this).balance, payable(msg.sender));
    }

    // / @inheritdoc IUsdnProtocol
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external onlyOwner {
        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external onlyOwner {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyOwner {
        s._rebalancer = newRebalancer;

        emit RebalancerUpdated(address(newRebalancer));
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        // zero minLeverage
        if (newMinLeverage <= 10 ** s.LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        if (newMinLeverage >= s._maxLeverage) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        s._minLeverage = newMinLeverage;
        emit MinLeverageUpdated(newMinLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        if (newMaxLeverage <= s._minLeverage) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        // `maxLeverage` greater than 100
        if (newMaxLeverage > 100 * 10 ** s.LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(newMaxLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        if (newValidationDeadline < 60) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        if (newValidationDeadline > 1 days) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        s._validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(newValidationDeadline);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyOwner {
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    // / @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        if (newLiquidationIteration > s.MAX_LIQUIDATION_ITERATION) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    // / @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    // / @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        if (newFundingSF > 10 ** s.FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit FundingSFUpdated(newFundingSF);
    }

    // / @inheritdoc IUsdnProtocol
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > s.BPS_DIVISOR) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit FeeBpsUpdated(newProtocolFeeBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setPositionFeeBps(uint16 newPositionFee) external onlyOwner {
        // `newPositionFee` greater than 20%
        if (newPositionFee > 2000) {
            revert UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit PositionFeeUpdated(newPositionFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setVaultFeeBps(uint16 newVaultFee) external onlyOwner {
        // `newVaultFee` greater than 20%
        if (newVaultFee > 2000) {
            revert UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit VaultFeeUpdated(newVaultFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancerBonusBps(uint16 newBonus) external onlyOwner {
        // `newBonus` greater than 100%
        if (newBonus > s.BPS_DIVISOR) {
            revert UsdnProtocolInvalidRebalancerBonus();
        }
        s._rebalancerBonusBps = newBonus;
        emit RebalancerBonusUpdated(newBonus);
    }

    // / @inheritdoc IUsdnProtocol
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyOwner {
        // `newRatio` greater than 5%
        if (newRatio > s.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit BurnSdexOnDepositRatioUpdated(newRatio);
    }

    // / @inheritdoc IUsdnProtocol
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyOwner {
        s._securityDepositValue = securityDepositValue;
        emit SecurityDepositValueUpdated(securityDepositValue);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeThreshold(uint256 newFeeThreshold) external onlyOwner {
        s._feeThreshold = newFeeThreshold;
        emit FeeThresholdUpdated(newFeeThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    // / @inheritdoc IUsdnProtocol
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyOwner {
        s._openExpoImbalanceLimitBps = newOpenLimitBps.toInt256();
        s._depositExpoImbalanceLimitBps = newDepositLimitBps.toInt256();

        if (newWithdrawalLimitBps != 0 && newWithdrawalLimitBps < newOpenLimitBps) {
            // withdrawal limit lower than open not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._withdrawalExpoImbalanceLimitBps = newWithdrawalLimitBps.toInt256();

        if (newCloseLimitBps != 0 && newCloseLimitBps < newDepositLimitBps) {
            // close limit lower than deposit not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        s._closeExpoImbalanceLimitBps = newCloseLimitBps.toInt256();

        // casts are safe here as values are safely casted earlier
        if (
            newLongImbalanceTargetBps > int256(newCloseLimitBps)
                || newLongImbalanceTargetBps < -int256(newWithdrawalLimitBps)
                || newLongImbalanceTargetBps < -int256(s.BPS_DIVISOR / 2) // The target cannot be lower than -50%
        ) {
            revert UsdnProtocolInvalidLongImbalanceTarget();
        }

        s._longImbalanceTargetBps = newLongImbalanceTargetBps;

        emit ImbalanceLimitsUpdated(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    // / @inheritdoc IUsdnProtocol
    function setTargetUsdnPrice(uint128 newPrice) external onlyOwner {
        if (newPrice > s._usdnRebaseThreshold) {
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        if (newPrice < uint128(10 ** s._priceFeedDecimals)) {
            // values smaller than $1 are not allowed
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        s._targetUsdnPrice = newPrice;
        emit TargetUsdnPriceUpdated(newPrice);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyOwner {
        if (newThreshold < s._targetUsdnPrice) {
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit UsdnRebaseThresholdUpdated(newThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseInterval(uint256 newInterval) external onlyOwner {
        s._usdnRebaseInterval = newInterval;
        emit UsdnRebaseIntervalUpdated(newInterval);
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLongPosition(uint256 newMinLongPosition) external onlyOwner {
        s._minLongPosition = newMinLongPosition;
        emit MinLongPositionUpdated(newMinLongPosition);

        IBaseRebalancer rebalancer = s._rebalancer;
        if (address(rebalancer) != address(0) && rebalancer.getMinAssetDeposit() < newMinLongPosition) {
            rebalancer.setMinAssetDeposit(newMinLongPosition);
        }
    }
}
