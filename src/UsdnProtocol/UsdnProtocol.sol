// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { UsdnProtocolBaseStorage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolActionsEntry } from "./UsdnProtocolActionsEntry.sol";
import { UsdnProtocolCoreEntry } from "./UsdnProtocolCoreEntry.sol";
import { UsdnProtocolLongEntry } from "./UsdnProtocolLongEntry.sol";
import { UsdnProtocolVaultEntry } from "./UsdnProtocolVaultEntry.sol";
import { UsdnProtocolSettersLibrary as settersLib } from "./UsdnProtocolSettersLibrary.sol";

contract UsdnProtocol is
    UsdnProtocolLongEntry,
    UsdnProtocolVaultEntry,
    UsdnProtocolCoreEntry,
    UsdnProtocolActionsEntry
{
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
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external onlyOwner {
        settersLib.setOracleMiddleware(s, newOracleMiddleware);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external onlyOwner {
        settersLib.setLiquidationRewardsManager(s, newLiquidationRewardsManager);
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyOwner {
        settersLib.setRebalancer(s, newRebalancer);
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        settersLib.setMinLeverage(s, newMinLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        settersLib.setMaxLeverage(s, newMaxLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        settersLib.setValidationDeadline(s, newValidationDeadline);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyOwner {
        settersLib.setLiquidationPenalty(s, newLiquidationPenalty);
    }

    // / @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        settersLib.setSafetyMarginBps(s, newSafetyMarginBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        settersLib.setLiquidationIteration(s, newLiquidationIteration);
    }

    // / @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        settersLib.setEMAPeriod(s, newEMAPeriod);
    }

    // / @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        settersLib.setFundingSF(s, newFundingSF);
    }

    // / @inheritdoc IUsdnProtocol
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        settersLib.setProtocolFeeBps(s, newProtocolFeeBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setPositionFeeBps(uint16 newPositionFee) external onlyOwner {
        settersLib.setPositionFeeBps(s, newPositionFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setVaultFeeBps(uint16 newVaultFee) external onlyOwner {
        settersLib.setVaultFeeBps(s, newVaultFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancerBonusBps(uint16 newBonus) external onlyOwner {
        settersLib.setRebalancerBonusBps(s, newBonus);
    }

    // / @inheritdoc IUsdnProtocol
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyOwner {
        settersLib.setSdexBurnOnDepositRatio(s, newRatio);
    }

    // / @inheritdoc IUsdnProtocol
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyOwner {
        settersLib.setSecurityDepositValue(s, securityDepositValue);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeThreshold(uint256 newFeeThreshold) external onlyOwner {
        settersLib.setFeeThreshold(s, newFeeThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        settersLib.setFeeCollector(s, newFeeCollector);
    }

    // / @inheritdoc IUsdnProtocol
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyOwner {
        settersLib.setExpoImbalanceLimits(
            s, newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    // / @inheritdoc IUsdnProtocol
    function setTargetUsdnPrice(uint128 newPrice) external onlyOwner {
        settersLib.setTargetUsdnPrice(s, newPrice);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyOwner {
        settersLib.setUsdnRebaseThreshold(s, newThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseInterval(uint256 newInterval) external onlyOwner {
        settersLib.setUsdnRebaseInterval(s, newInterval);
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLongPosition(uint256 newMinLongPosition) external onlyOwner {
        settersLib.setMinLongPosition(s, newMinLongPosition);
    }
}
