// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { ProtocolAction, Position, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { UsdnProtocolLongEntry } from "src/UsdnProtocol/UsdnProtocolLongEntry.sol";
import { UsdnProtocolCommonEntry } from "src/UsdnProtocol/UsdnProtocolCommonEntry.sol";
import { UsdnProtocolVaultEntry } from "src/UsdnProtocol/UsdnProtocolVaultEntry.sol";
import { UsdnProtocolActionsEntry } from "src/UsdnProtocol/UsdnProtocolActionsEntry.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

contract UsdnProtocolProxy is
    UsdnProtocolLongEntry,
    UsdnProtocolVaultEntry,
    UsdnProtocolCommonEntry,
    UsdnProtocolActionsEntry,
    IUsdnProtocolEvents,
    Ownable
{
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param sdex The SDEX ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param tickSpacing The positions tick spacing.
     * @param feeCollector The address of the fee collector.
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
        UsdnProtocolBaseStorage(usdn, sdex, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector)
    { }

    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external onlyOwner {
        // check address zero middleware
        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolInvalidMiddlewareAddress();
        }
        s._oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external onlyOwner {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        s._liquidationRewardsManager = newLiquidationRewardsManager;

        emit LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        // zero minLeverage
        if (newMinLeverage <= 10 ** s.LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        // minLeverage greater or equal maxLeverage
        if (newMinLeverage >= s._maxLeverage) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        s._minLeverage = newMinLeverage;
        emit MinLeverageUpdated(newMinLeverage);
    }

    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        // maxLeverage lower or equal minLeverage
        if (newMaxLeverage <= s._minLeverage) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        // maxLeverage greater than max 100
        if (newMaxLeverage > 100 * 10 ** s.LEVERAGE_DECIMALS) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        s._maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(newMaxLeverage);
    }

    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        // validation deadline lower than min 1 minute
        if (newValidationDeadline < 60) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        // validation deadline greater than max 1 day
        if (newValidationDeadline > 1 days) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        s._validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(newValidationDeadline);
    }

    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyOwner {
        // liquidationPenalty greater than max 15
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        s._liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than max 2000: 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        s._safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        // newLiquidationIteration greater than MAX_LIQUIDATION_ITERATION
        if (newLiquidationIteration > s.MAX_LIQUIDATION_ITERATION) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        s._liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        // EMAPeriod is greater than max 3 months
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        s._EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        // newFundingSF is greater than max
        if (newFundingSF > 10 ** s.FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidFundingSF();
        }

        s._fundingSF = newFundingSF;
        emit FundingSFUpdated(newFundingSF);
    }

    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > s.BPS_DIVISOR) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        s._protocolFeeBps = newProtocolFeeBps;
        emit FeeBpsUpdated(newProtocolFeeBps);
    }

    function setPositionFeeBps(uint16 newPositionFee) external onlyOwner {
        // newPositionFee greater than max 2000: 20%
        if (newPositionFee > 2000) {
            revert UsdnProtocolInvalidPositionFee();
        }
        s._positionFeeBps = newPositionFee;
        emit PositionFeeUpdated(newPositionFee);
    }

    function setVaultFeeBps(uint16 newVaultFee) external onlyOwner {
        // newVaultFee greater than max 2000: 20%
        if (newVaultFee > 2000) {
            revert UsdnProtocolInvalidVaultFee();
        }
        s._vaultFeeBps = newVaultFee;
        emit PositionFeeUpdated(newVaultFee);
    }

    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyOwner {
        // If newRatio is greater than 5%
        if (newRatio > s.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20) {
            revert UsdnProtocolInvalidBurnSdexOnDepositRatio();
        }

        s._sdexBurnOnDepositRatio = newRatio;

        emit BurnSdexOnDepositRatioUpdated(newRatio);
    }

    function setSecurityDepositValue(uint64 securityDepositValue) external onlyOwner {
        s._securityDepositValue = securityDepositValue;
        emit SecurityDepositValueUpdated(securityDepositValue);
    }

    function setFeeThreshold(uint256 newFeeThreshold) external onlyOwner {
        s._feeThreshold = newFeeThreshold;
        emit FeeThresholdUpdated(newFeeThreshold);
    }

    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        s._feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps
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

        emit ImbalanceLimitsUpdated(newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps);
    }

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

    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyOwner {
        if (newThreshold < s._targetUsdnPrice) {
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        s._usdnRebaseThreshold = newThreshold;
        emit UsdnRebaseThresholdUpdated(newThreshold);
    }

    function setUsdnRebaseInterval(uint256 newInterval) external onlyOwner {
        s._usdnRebaseInterval = newInterval;
        emit UsdnRebaseIntervalUpdated(newInterval);
    }

    function setMinLongPosition(uint256 newMinLongPosition) external onlyOwner {
        s._minLongPosition = newMinLongPosition;
        emit MinLongPositionUpdated(newMinLongPosition);
    }
}
