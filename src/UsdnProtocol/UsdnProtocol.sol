// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolActions } from "./UsdnProtocolActions.sol";
import { UsdnProtocolCore } from "./UsdnProtocolCore.sol";
import { UsdnProtocolLong } from "./UsdnProtocolLong.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolVault } from "./UsdnProtocolVault.sol";
import { UsdnProtocolSettersLibrary as Setters } from "./libraries/UsdnProtocolSettersLibrary.sol";

contract UsdnProtocol is IUsdnProtocol, UsdnProtocolLong, UsdnProtocolVault, UsdnProtocolCore, UsdnProtocolActions {
    /**
     * @notice Constructor
     * @param usdn The USDN ERC20 contract
     * @param sdex The SDEX ERC20 contract
     * @param asset The asset ERC20 contract (wstETH)
     * @param oracleMiddleware The oracle middleware contract
     * @param liquidationRewardsManager The liquidation rewards manager contract
     * @param tickSpacing The positions tick spacing
     * @param feeCollector The address of the fee collector
     * @param roles The protocol roles
     */
    constructor(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Roles memory roles
    )
        UsdnProtocolStorage(
            usdn,
            sdex,
            asset,
            oracleMiddleware,
            liquidationRewardsManager,
            tickSpacing,
            feeCollector,
            roles
        )
    { }

    /// @inheritdoc IUsdnProtocol
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external onlyRole(CONFIG_ROLE) {
        Setters.setOracleMiddleware(s, newOracleMiddleware);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager)
        external
        onlyRole(CONFIG_ROLE)
    {
        Setters.setLiquidationRewardsManager(s, newLiquidationRewardsManager);
    }

    /// @inheritdoc IUsdnProtocol
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyRole(CONFIG_ROLE) {
        Setters.setRebalancer(s, newRebalancer);
    }

    /// @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyRole(ACTION_ROLE) {
        Setters.setMinLeverage(s, newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyRole(ACTION_ROLE) {
        Setters.setMaxLeverage(s, newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyRole(ACTION_ROLE) {
        Setters.setValidationDeadline(s, newValidationDeadline);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyRole(ACTION_ROLE) {
        Setters.setLiquidationPenalty(s, newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyRole(ACTION_ROLE) {
        Setters.setSafetyMarginBps(s, newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyRole(ACTION_ROLE) {
        Setters.setLiquidationIteration(s, newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyRole(ACTION_ROLE) {
        Setters.setEMAPeriod(s, newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyRole(ACTION_ROLE) {
        Setters.setFundingSF(s, newFundingSF);
    }

    /// @inheritdoc IUsdnProtocol
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyRole(ACTION_ROLE) {
        Setters.setProtocolFeeBps(s, newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setPositionFeeBps(uint16 newPositionFee) external onlyRole(ACTION_ROLE) {
        Setters.setPositionFeeBps(s, newPositionFee);
    }

    /// @inheritdoc IUsdnProtocol
    function setVaultFeeBps(uint16 newVaultFee) external onlyRole(ACTION_ROLE) {
        Setters.setVaultFeeBps(s, newVaultFee);
    }

    /// @inheritdoc IUsdnProtocol
    function setRebalancerBonusBps(uint16 newBonus) external onlyRole(ACTION_ROLE) {
        Setters.setRebalancerBonusBps(s, newBonus);
    }

    /// @inheritdoc IUsdnProtocol
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyRole(ACTION_ROLE) {
        Setters.setSdexBurnOnDepositRatio(s, newRatio);
    }

    /// @inheritdoc IUsdnProtocol
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyRole(ACTION_ROLE) {
        Setters.setSecurityDepositValue(s, securityDepositValue);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeThreshold(uint256 newFeeThreshold) external onlyRole(ACTION_ROLE) {
        Setters.setFeeThreshold(s, newFeeThreshold);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeCollector(address newFeeCollector) external onlyRole(CONFIG_ROLE) {
        Setters.setFeeCollector(s, newFeeCollector);
    }

    /// @inheritdoc IUsdnProtocol
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyRole(ACTION_ROLE) {
        Setters.setExpoImbalanceLimits(
            s, newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    /// @inheritdoc IUsdnProtocol
    function setTargetUsdnPrice(uint128 newPrice) external onlyRole(ACTION_ROLE) {
        Setters.setTargetUsdnPrice(s, newPrice);
    }

    /// @inheritdoc IUsdnProtocol
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyRole(ACTION_ROLE) {
        Setters.setUsdnRebaseThreshold(s, newThreshold);
    }

    /// @inheritdoc IUsdnProtocol
    function setUsdnRebaseInterval(uint256 newInterval) external onlyRole(ACTION_ROLE) {
        Setters.setUsdnRebaseInterval(s, newInterval);
    }

    /// @inheritdoc IUsdnProtocol
    function setMinLongPosition(uint256 newMinLongPosition) external onlyRole(ACTION_ROLE) {
        Setters.setMinLongPosition(s, newMinLongPosition);
    }
}
