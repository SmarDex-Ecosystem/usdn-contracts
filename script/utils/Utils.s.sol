// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract Utils is Script {
    string constant FUNC_CLASHES_SCRIPT_PATH = "script/utils/functionClashes.ts";
    string constant IMPL_INITIALIZATION_SCRIPT_PATH = "script/utils/checkImplementationInitialization.ts";

    // to run the script in standalone mode
    function run() external {
        validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");
    }

    /**
     * @notice Validate the Usdn protocol
     * @dev Call this function to validate the Usdn protocol before deploying it
     */
    function validateProtocol(string memory implementationContractName, string memory fallbackContractName) public {
        string[] memory inputs = _buildCommandFunctionClashes(implementationContractName, fallbackContractName);
        runFfiCommand(inputs);

        string[] memory inputs2 = _buildCommandCheckImplementationInitialization(implementationContractName);
        runFfiCommand(inputs2);
    }

    /**
     * @notice Validate the Usdn protocol configuration by calling all protocol setters with the current values
     * @param usdnProtocol The Usdn protocol instance
     * @param admin The default admin address
     */
    function validateProtocolConfig(IUsdnProtocol usdnProtocol, address admin) external {
        vm.startPrank(admin);

        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, admin);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, admin);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, admin);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, admin);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, admin);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, admin);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, admin);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, admin);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, admin);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, admin);

        usdnProtocol.setOracleMiddleware(usdnProtocol.getOracleMiddleware());
        usdnProtocol.setLiquidationRewardsManager(usdnProtocol.getLiquidationRewardsManager());
        usdnProtocol.setRebalancer(usdnProtocol.getRebalancer());
        usdnProtocol.setFeeCollector(usdnProtocol.getFeeCollector());
        usdnProtocol.setValidatorDeadlines(
            usdnProtocol.getLowLatencyValidatorDeadline(), usdnProtocol.getOnChainValidatorDeadline()
        );
        usdnProtocol.setMinLeverage(usdnProtocol.getMinLeverage());
        usdnProtocol.setMaxLeverage(usdnProtocol.getMaxLeverage());
        usdnProtocol.setLiquidationPenalty(usdnProtocol.getLiquidationPenalty());
        usdnProtocol.setEMAPeriod(usdnProtocol.getEMAPeriod());
        usdnProtocol.setFundingSF(usdnProtocol.getFundingSF());
        usdnProtocol.setProtocolFeeBps(usdnProtocol.getProtocolFeeBps());
        usdnProtocol.setPositionFeeBps(usdnProtocol.getPositionFeeBps());
        usdnProtocol.setVaultFeeBps(usdnProtocol.getVaultFeeBps());
        usdnProtocol.setSdexRewardsRatioBps(usdnProtocol.getSdexRewardsRatioBps());
        usdnProtocol.setRebalancerBonusBps(usdnProtocol.getRebalancerBonusBps());
        usdnProtocol.setSdexBurnOnDepositRatio(usdnProtocol.getSdexBurnOnDepositRatio());
        usdnProtocol.setSecurityDepositValue(usdnProtocol.getSecurityDepositValue());
        usdnProtocol.setExpoImbalanceLimits(
            uint256(usdnProtocol.getOpenExpoImbalanceLimitBps()),
            uint256(usdnProtocol.getDepositExpoImbalanceLimitBps()),
            uint256(usdnProtocol.getWithdrawalExpoImbalanceLimitBps()),
            uint256(usdnProtocol.getCloseExpoImbalanceLimitBps()),
            uint256(usdnProtocol.getRebalancerCloseExpoImbalanceLimitBps()),
            usdnProtocol.getLongImbalanceTargetBps()
        );
        usdnProtocol.setMinLongPosition(usdnProtocol.getMinLongPosition());
        usdnProtocol.setSafetyMarginBps(usdnProtocol.getSafetyMarginBps());
        usdnProtocol.setLiquidationIteration(usdnProtocol.getLiquidationIteration());
        usdnProtocol.setFeeThreshold(usdnProtocol.getFeeThreshold());
        usdnProtocol.setTargetUsdnPrice(usdnProtocol.getTargetUsdnPrice());
        usdnProtocol.setUsdnRebaseThreshold(usdnProtocol.getUsdnRebaseThreshold());

        vm.stopPrank();
    }

    /**
     * @notice Clean the `out` directory and build the contracts
     * @dev Call this function to clean the `out` directory and build the contracts
     */
    function cleanAndBuildContracts() external {
        _cleanOutDir();
        _buildContracts();
    }

    /**
     * @notice Function to run an external command with ffi
     * @dev This function reverts if the command fails
     * @param inputs The command to run
     * @return The result of the command, printed to stdout
     */
    function runFfiCommand(string[] memory inputs) public returns (bytes memory) {
        Vm.FfiResult memory result = vm.tryFfi(inputs);

        if (result.exitCode != 0) {
            revert(string(abi.encodePacked("Failed to run bash command: ", result.stdout)));
        } else {
            return (result.stdout);
        }
    }

    /**
     * @notice Clean the `out` directory
     * @dev Call this function to clean the `out` directory
     */
    function _cleanOutDir() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "forge";
        inputs[1] = "clean";
        runFfiCommand(inputs);
    }

    /**
     * @notice Build the contracts
     * @dev Call this function to build the contracts
     */
    function _buildContracts() internal {
        string[] memory inputs = new string[](3);
        inputs[0] = "forge";
        inputs[1] = "build";
        inputs[2] = "script";
        runFfiCommand(inputs);
    }

    /**
     * @notice Build the command to run the functionClashes.ts script
     * @return inputs_ The command to run the functionClashes.ts script
     */
    function _buildCommandFunctionClashes(string memory implementationFile, string memory fallbackFile)
        internal
        pure
        returns (string[] memory inputs_)
    {
        inputs_ = new string[](8);
        uint8 i;

        // create the command to run the functionClashes.ts script:
        // npx tsx FUNC_CLASHES_SCRIPT_PATH UsdnProtocolImpl UsdnProtocolFallback -c
        // AccessControlDefaultAdminRulesUpgradeable PausableUpgradeable
        inputs_[i++] = "npx";
        inputs_[i++] = "tsx";
        inputs_[i++] = FUNC_CLASHES_SCRIPT_PATH;
        inputs_[i++] = implementationFile;
        inputs_[i++] = fallbackFile;
        inputs_[i++] = "-c";
        inputs_[i++] = "AccessControlDefaultAdminRulesUpgradeable";
        inputs_[i] = "PausableUpgradeable";
    }

    /**
     * @notice Build the command to run the checkImplementationInitialization.ts script
     * @return inputs_ The command to run the checkImplementationInitialization.ts script
     */
    function _buildCommandCheckImplementationInitialization(string memory implementationName)
        internal
        pure
        returns (string[] memory inputs_)
    {
        inputs_ = new string[](4);
        uint8 i;

        // create the command to run the checkImplementationInitialization.ts script:
        // npx tsx IMPL_INITIALIZATION_SCRIPT_PATH UsdnProtocolImpl.sol
        inputs_[i++] = "npx";
        inputs_[i++] = "tsx";
        inputs_[i++] = IMPL_INITIALIZATION_SCRIPT_PATH;
        inputs_[i] = implementationName;
    }
}
