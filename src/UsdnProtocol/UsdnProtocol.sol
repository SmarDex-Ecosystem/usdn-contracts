// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "../interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolActions } from "./UsdnProtocolActions.sol";
import { UsdnProtocolLong } from "./UsdnProtocolLong.sol";
import { UsdnProtocolStorage } from "./UsdnProtocolStorage.sol";
import { UsdnProtocolVault } from "./UsdnProtocolVault.sol";
import { UsdnProtocolSettersLibrary as Setters } from "./libraries/UsdnProtocolSettersLibrary.sol";
import { console2 } from "forge-std/Test.sol";

contract UsdnProtocol is UsdnProtocolLong, UsdnProtocolVault, UsdnProtocolActions {
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

    /* -------------------------------------------------------------------------- */
    /*                              SET_EXTERNAL_ROLE                             */
    /* -------------------------------------------------------------------------- */

    // / @inheritdoc IUsdnProtocol
    function setOracleMiddleware(IBaseOracleMiddleware newOracleMiddleware) external onlyRole(SET_EXTERNAL_ROLE) {
        Setters.setOracleMiddleware(s, newOracleMiddleware);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeCollector(address newFeeCollector) external onlyRole(SET_EXTERNAL_ROLE) {
        Setters.setFeeCollector(s, newFeeCollector);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager)
        external
        onlyRole(SET_EXTERNAL_ROLE)
    {
        Setters.setLiquidationRewardsManager(s, newLiquidationRewardsManager);
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancer(IBaseRebalancer newRebalancer) external onlyRole(SET_EXTERNAL_ROLE) {
        Setters.setRebalancer(s, newRebalancer);
    }

    /* -------------------------------------------------------------------------- */
    /*                           CRITICAL_FUNCTIONS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    // / @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyRole(CRITICAL_FUNCTIONS_ROLE) {
        Setters.setValidationDeadline(s, newValidationDeadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                          SET_PROTOCOL_PARAMS_ROLE                          */
    /* -------------------------------------------------------------------------- */

    // / @inheritdoc IUsdnProtocol
    function setMinLongPosition(uint256 newMinLongPosition) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setMinLongPosition(s, newMinLongPosition);
    }

    // / @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setMinLeverage(s, newMinLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setMaxLeverage(s, newMaxLeverage);
    }

    // / @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setEMAPeriod(s, newEMAPeriod);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint8 newLiquidationPenalty) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setLiquidationPenalty(s, newLiquidationPenalty);
    }

    // / @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setFundingSF(s, newFundingSF);
    }

    // / @inheritdoc IUsdnProtocol
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setProtocolFeeBps(s, newProtocolFeeBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setPositionFeeBps(uint16 newPositionFee) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setPositionFeeBps(s, newPositionFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setVaultFeeBps(uint16 newVaultFee) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setVaultFeeBps(s, newVaultFee);
    }

    // / @inheritdoc IUsdnProtocol
    function setRebalancerBonusBps(uint16 newBonus) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setRebalancerBonusBps(s, newBonus);
    }

    // / @inheritdoc IUsdnProtocol
    function setSdexBurnOnDepositRatio(uint32 newRatio) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setSdexBurnOnDepositRatio(s, newRatio);
    }

    // / @inheritdoc IUsdnProtocol
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setExpoImbalanceLimits(
            s, newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    // / @inheritdoc IUsdnProtocol
    function setSecurityDepositValue(uint64 securityDepositValue) external onlyRole(SET_PROTOCOL_PARAMS_ROLE) {
        Setters.setSecurityDepositValue(s, securityDepositValue);
    }

    /* -------------------------------------------------------------------------- */
    /*                              SET_OPTIONS_ROLE                              */
    /* -------------------------------------------------------------------------- */

    // / @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyRole(SET_OPTIONS_ROLE) {
        Setters.setSafetyMarginBps(s, newSafetyMarginBps);
    }

    // / @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyRole(SET_OPTIONS_ROLE) {
        Setters.setLiquidationIteration(s, newLiquidationIteration);
    }

    // / @inheritdoc IUsdnProtocol
    function setFeeThreshold(uint256 newFeeThreshold) external onlyRole(SET_OPTIONS_ROLE) {
        Setters.setFeeThreshold(s, newFeeThreshold);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SET_USDN_PARAMS_ROLE                            */
    /* -------------------------------------------------------------------------- */

    // / @inheritdoc IUsdnProtocol
    function setTargetUsdnPrice(uint128 newPrice) external onlyRole(SET_USDN_PARAMS_ROLE) {
        Setters.setTargetUsdnPrice(s, newPrice);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyRole(SET_USDN_PARAMS_ROLE) {
        Setters.setUsdnRebaseThreshold(s, newThreshold);
    }

    // / @inheritdoc IUsdnProtocol
    function setUsdnRebaseInterval(uint256 newInterval) external onlyRole(SET_USDN_PARAMS_ROLE) {
        Setters.setUsdnRebaseInterval(s, newInterval);
    }

    function _delegate(address implementation) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())

            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // TO DO : remove this function
    function setUtilsContract(address newUtilsContract) external {
        s._utilsContract = newUtilsContract;
    }

    function getUtilsContract() external view returns (address) {
        return s._utilsContract;
    }

    fallback() external payable {
        _delegate(s._utilsContract);
    }
}
