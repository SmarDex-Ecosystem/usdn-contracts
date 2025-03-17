// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @notice Set the USDN protocol parameters to a new protocol.
 * @dev When running this script, a prompt will ask for the new USDN protocol address. It will then grant all setter
 * roles to the default admin and set the protocol parameters to the current values.
 */
contract SetUsdnParams is Script {
    IUsdnProtocol constant ACTUAL_PROTOCOL = IUsdnProtocol(0x656cB8C6d154Aad29d8771384089be5B5141f01a);

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

        newUsdnProtocol.setOracleMiddleware(ACTUAL_PROTOCOL.getOracleMiddleware());
        newUsdnProtocol.setLiquidationRewardsManager(ACTUAL_PROTOCOL.getLiquidationRewardsManager());
        newUsdnProtocol.setRebalancer(ACTUAL_PROTOCOL.getRebalancer());
        newUsdnProtocol.setFeeCollector(ACTUAL_PROTOCOL.getFeeCollector());
        newUsdnProtocol.setValidatorDeadlines(
            ACTUAL_PROTOCOL.getLowLatencyValidatorDeadline(), ACTUAL_PROTOCOL.getOnChainValidatorDeadline()
        );
        newUsdnProtocol.setMinLeverage(ACTUAL_PROTOCOL.getMinLeverage());
        newUsdnProtocol.setMaxLeverage(ACTUAL_PROTOCOL.getMaxLeverage());
        newUsdnProtocol.setLiquidationPenalty(ACTUAL_PROTOCOL.getLiquidationPenalty());
        newUsdnProtocol.setEMAPeriod(ACTUAL_PROTOCOL.getEMAPeriod());
        newUsdnProtocol.setFundingSF(ACTUAL_PROTOCOL.getFundingSF());
        newUsdnProtocol.setProtocolFeeBps(ACTUAL_PROTOCOL.getProtocolFeeBps());
        newUsdnProtocol.setPositionFeeBps(ACTUAL_PROTOCOL.getPositionFeeBps());
        newUsdnProtocol.setVaultFeeBps(ACTUAL_PROTOCOL.getVaultFeeBps());
        newUsdnProtocol.setSdexRewardsRatioBps(ACTUAL_PROTOCOL.getSdexRewardsRatioBps());
        newUsdnProtocol.setRebalancerBonusBps(ACTUAL_PROTOCOL.getRebalancerBonusBps());
        newUsdnProtocol.setSdexBurnOnDepositRatio(ACTUAL_PROTOCOL.getSdexBurnOnDepositRatio());
        newUsdnProtocol.setSecurityDepositValue(ACTUAL_PROTOCOL.getSecurityDepositValue());
        newUsdnProtocol.setExpoImbalanceLimits(
            uint256(ACTUAL_PROTOCOL.getOpenExpoImbalanceLimitBps()),
            uint256(ACTUAL_PROTOCOL.getDepositExpoImbalanceLimitBps()),
            uint256(ACTUAL_PROTOCOL.getWithdrawalExpoImbalanceLimitBps()),
            uint256(ACTUAL_PROTOCOL.getCloseExpoImbalanceLimitBps()),
            uint256(ACTUAL_PROTOCOL.getRebalancerCloseExpoImbalanceLimitBps()),
            ACTUAL_PROTOCOL.getLongImbalanceTargetBps()
        );
        newUsdnProtocol.setMinLongPosition(ACTUAL_PROTOCOL.getMinLongPosition());
        newUsdnProtocol.setSafetyMarginBps(ACTUAL_PROTOCOL.getSafetyMarginBps());
        newUsdnProtocol.setLiquidationIteration(ACTUAL_PROTOCOL.getLiquidationIteration());
        newUsdnProtocol.setFeeThreshold(ACTUAL_PROTOCOL.getFeeThreshold());
        newUsdnProtocol.setTargetUsdnPrice(ACTUAL_PROTOCOL.getTargetUsdnPrice());
        newUsdnProtocol.setUsdnRebaseThreshold(ACTUAL_PROTOCOL.getUsdnRebaseThreshold());

        vm.stopBroadcast();
    }
}
