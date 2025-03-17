// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @notice Transfers the USDN protocol parameters to a new protocol.
 * @dev Running this script will prompt for the new USDN protocol address.
 * It will then grant all setter roles to the default admin and apply the current protocol parameters.
 */
contract SetUsdnParams is Script {
    IUsdnProtocol constant CURRENT_PROTOCOL = IUsdnProtocol(0x656cB8C6d154Aad29d8771384089be5B5141f01a);

    function run() external {
        IUsdnProtocol newUsdnProtocol =
            IUsdnProtocol(vm.parseAddress(vm.prompt("enter the new usdn protocol address: ")));
        address admin = newUsdnProtocol.defaultAdmin();

        vm.startBroadcast(admin);

        newUsdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, admin);
        newUsdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, admin);

        newUsdnProtocol.setOracleMiddleware(CURRENT_PROTOCOL.getOracleMiddleware());
        newUsdnProtocol.setLiquidationRewardsManager(CURRENT_PROTOCOL.getLiquidationRewardsManager());
        newUsdnProtocol.setRebalancer(CURRENT_PROTOCOL.getRebalancer());
        newUsdnProtocol.setFeeCollector(CURRENT_PROTOCOL.getFeeCollector());
        newUsdnProtocol.setValidatorDeadlines(
            CURRENT_PROTOCOL.getLowLatencyValidatorDeadline(), CURRENT_PROTOCOL.getOnChainValidatorDeadline()
        );
        newUsdnProtocol.setMinLeverage(CURRENT_PROTOCOL.getMinLeverage());
        newUsdnProtocol.setMaxLeverage(CURRENT_PROTOCOL.getMaxLeverage());
        newUsdnProtocol.setLiquidationPenalty(CURRENT_PROTOCOL.getLiquidationPenalty());
        newUsdnProtocol.setEMAPeriod(CURRENT_PROTOCOL.getEMAPeriod());
        newUsdnProtocol.setFundingSF(CURRENT_PROTOCOL.getFundingSF());
        newUsdnProtocol.setProtocolFeeBps(CURRENT_PROTOCOL.getProtocolFeeBps());
        newUsdnProtocol.setPositionFeeBps(CURRENT_PROTOCOL.getPositionFeeBps());
        newUsdnProtocol.setVaultFeeBps(CURRENT_PROTOCOL.getVaultFeeBps());
        newUsdnProtocol.setSdexRewardsRatioBps(CURRENT_PROTOCOL.getSdexRewardsRatioBps());
        newUsdnProtocol.setRebalancerBonusBps(CURRENT_PROTOCOL.getRebalancerBonusBps());
        newUsdnProtocol.setSdexBurnOnDepositRatio(CURRENT_PROTOCOL.getSdexBurnOnDepositRatio());
        newUsdnProtocol.setSecurityDepositValue(CURRENT_PROTOCOL.getSecurityDepositValue());
        newUsdnProtocol.setExpoImbalanceLimits(
            uint256(CURRENT_PROTOCOL.getOpenExpoImbalanceLimitBps()),
            uint256(CURRENT_PROTOCOL.getDepositExpoImbalanceLimitBps()),
            uint256(CURRENT_PROTOCOL.getWithdrawalExpoImbalanceLimitBps()),
            uint256(CURRENT_PROTOCOL.getCloseExpoImbalanceLimitBps()),
            uint256(CURRENT_PROTOCOL.getRebalancerCloseExpoImbalanceLimitBps()),
            CURRENT_PROTOCOL.getLongImbalanceTargetBps()
        );
        newUsdnProtocol.setMinLongPosition(CURRENT_PROTOCOL.getMinLongPosition());
        newUsdnProtocol.setSafetyMarginBps(CURRENT_PROTOCOL.getSafetyMarginBps());
        newUsdnProtocol.setLiquidationIteration(CURRENT_PROTOCOL.getLiquidationIteration());
        newUsdnProtocol.setFeeThreshold(CURRENT_PROTOCOL.getFeeThreshold());
        newUsdnProtocol.setTargetUsdnPrice(CURRENT_PROTOCOL.getTargetUsdnPrice());
        newUsdnProtocol.setUsdnRebaseThreshold(CURRENT_PROTOCOL.getUsdnRebaseThreshold());

        vm.stopBroadcast();
    }
}
