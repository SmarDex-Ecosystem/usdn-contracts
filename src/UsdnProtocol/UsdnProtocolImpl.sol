// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { UUPSUpgradeable } from "solady/src/utils/UUPSUpgradeable.sol";

import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolFallback } from "../interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolImpl } from "../interfaces/UsdnProtocol/IUsdnProtocolImpl.sol";
import { UsdnProtocolActions } from "./UsdnProtocolActions.sol";
import { UsdnProtocolCore } from "./UsdnProtocolCore.sol";
import { UsdnProtocolLong } from "./UsdnProtocolLong.sol";
import { UsdnProtocolVault } from "./UsdnProtocolVault.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./libraries/UsdnProtocolUtilsLibrary.sol";

contract UsdnProtocolImpl is
    IUsdnProtocolErrors,
    IUsdnProtocolImpl,
    UsdnProtocolActions,
    UsdnProtocolCore,
    UsdnProtocolVault,
    UsdnProtocolLong,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IUsdnProtocolImpl
    function initializeStorage(InitStorage calldata initStorage) public initializer {
        Storage storage s = Utils._getMainStorage();

        __AccessControlDefaultAdminRules_init(0, msg.sender);
        __initializeReentrancyGuard_init();
        __Pausable_init();
        __EIP712_init("UsdnProtocol", "1");

        _setRoleAdmin(Constants.SET_EXTERNAL_ROLE, Constants.ADMIN_SET_EXTERNAL_ROLE);
        _setRoleAdmin(Constants.CRITICAL_FUNCTIONS_ROLE, Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE);
        _setRoleAdmin(Constants.SET_PROTOCOL_PARAMS_ROLE, Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE);
        _setRoleAdmin(Constants.SET_USDN_PARAMS_ROLE, Constants.ADMIN_SET_USDN_PARAMS_ROLE);
        _setRoleAdmin(Constants.SET_OPTIONS_ROLE, Constants.ADMIN_SET_OPTIONS_ROLE);
        _setRoleAdmin(Constants.PROXY_UPGRADE_ROLE, Constants.ADMIN_PROXY_UPGRADE_ROLE);
        _setRoleAdmin(Constants.PAUSER_ROLE, Constants.ADMIN_PAUSER_ROLE);
        _setRoleAdmin(Constants.UNPAUSER_ROLE, Constants.ADMIN_UNPAUSER_ROLE);

        s._minLeverage = initStorage.minLeverage;
        s._maxLeverage = initStorage.maxLeverage;
        s._lowLatencyValidatorDeadline = initStorage.lowLatencyValidatorDeadline;
        s._onChainValidatorDeadline = initStorage.onChainValidatorDeadline;
        s._safetyMarginBps = initStorage.safetyMarginBps;
        s._liquidationIteration = initStorage.liquidationIteration;
        s._protocolFeeBps = initStorage.protocolFeeBps;
        s._rebalancerBonusBps = initStorage.rebalancerBonusBps;
        s._liquidationPenalty = initStorage.liquidationPenalty;
        s._EMAPeriod = initStorage.EMAPeriod;
        s._fundingSF = initStorage.fundingSF;
        s._feeThreshold = initStorage.feeThreshold;
        s._openExpoImbalanceLimitBps = initStorage.openExpoImbalanceLimitBps;
        s._withdrawalExpoImbalanceLimitBps = initStorage.withdrawalExpoImbalanceLimitBps;
        s._depositExpoImbalanceLimitBps = initStorage.depositExpoImbalanceLimitBps;
        s._closeExpoImbalanceLimitBps = initStorage.closeExpoImbalanceLimitBps;
        s._rebalancerCloseExpoImbalanceLimitBps = initStorage.rebalancerCloseExpoImbalanceLimitBps;
        s._longImbalanceTargetBps = initStorage.longImbalanceTargetBps;
        s._positionFeeBps = initStorage.positionFeeBps;
        s._vaultFeeBps = initStorage.vaultFeeBps;
        s._sdexRewardsRatioBps = initStorage.sdexRewardsRatioBps;
        s._sdexBurnOnDepositRatio = initStorage.sdexBurnOnDepositRatio;
        s._securityDepositValue = initStorage.securityDepositValue;
        s._EMA = initStorage.EMA;

        // since all USDN must be minted by the protocol, we check that the total supply is 0
        if (initStorage.usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(initStorage.usdn));
        }
        if (initStorage.feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        s._usdn = initStorage.usdn;
        s._sdex = initStorage.sdex;
        // make sure the USDN and SDEX tokens have the same number of decimals
        if (
            initStorage.usdn.decimals() != Constants.TOKENS_DECIMALS
                || initStorage.sdex.decimals() != Constants.TOKENS_DECIMALS
        ) {
            revert UsdnProtocolInvalidTokenDecimals();
        }

        s._usdnMinDivisor = initStorage.usdn.MIN_DIVISOR();
        s._asset = initStorage.asset;
        uint8 assetDecimals = initStorage.asset.decimals();
        s._assetDecimals = assetDecimals;
        if (assetDecimals < Constants.FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidAssetDecimals(assetDecimals);
        }
        s._oracleMiddleware = initStorage.oracleMiddleware;
        uint8 priceFeedDecimals = initStorage.oracleMiddleware.getDecimals();
        s._priceFeedDecimals = priceFeedDecimals;
        s._liquidationRewardsManager = initStorage.liquidationRewardsManager;
        s._tickSpacing = initStorage.tickSpacing;
        s._feeCollector = initStorage.feeCollector;

        s._targetUsdnPrice = initStorage.targetUsdnPrice;
        s._usdnRebaseThreshold = initStorage.usdnRebaseThreshold;
        s._minLongPosition = initStorage.minLongPosition;
        s._protocolFallbackAddr = initStorage.protocolFallbackAddr;
    }

    /**
     * @inheritdoc UUPSUpgradeable
     * @notice Verifies that the caller is allowed to upgrade the protocol.
     * @param implementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address implementation) internal override onlyRole(Constants.PROXY_UPGRADE_ROLE) { }

    /**
     * @notice Delegates the call to the fallback contract.
     * @param protocolFallbackAddr The address of the fallback contract.
     */
    function _delegate(address protocolFallbackAddr) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), protocolFallbackAddr, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @notice Delegates the call to the fallback contract if the function signature contained in the transaction data
     * does not match any function in the implementation contract.
     */
    fallback() external {
        _delegate(Utils._getMainStorage()._protocolFallbackAddr);
    }
}
