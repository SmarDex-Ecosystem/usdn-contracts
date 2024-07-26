// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseLiquidationRewardsManager } from "../interfaces/OracleMiddleware/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { UsdnProtocolActions } from "./UsdnProtocolActions.sol";
import { UsdnProtocolCore } from "./UsdnProtocolCore.sol";
import { UsdnProtocolLong } from "./UsdnProtocolLong.sol";
import { UsdnProtocolVault } from "./UsdnProtocolVault.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./libraries/UsdnProtocolConstantsLibrary.sol";

contract UsdnProtocol is UsdnProtocolLong, UsdnProtocolVault, UsdnProtocolCore, UsdnProtocolActions {
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
    function initializeStorage(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Roles memory roles
    ) public {
        __AccessControlDefaultAdminRules_init(0, msg.sender);
        // roles
        _setRoleAdmin(SET_EXTERNAL_ROLE, ADMIN_SET_EXTERNAL_ROLE);
        _setRoleAdmin(CRITICAL_FUNCTIONS_ROLE, ADMIN_CRITICAL_FUNCTIONS_ROLE);
        _setRoleAdmin(SET_PROTOCOL_PARAMS_ROLE, ADMIN_SET_PROTOCOL_PARAMS_ROLE);
        _setRoleAdmin(SET_USDN_PARAMS_ROLE, ADMIN_SET_USDN_PARAMS_ROLE);
        _setRoleAdmin(SET_OPTIONS_ROLE, ADMIN_SET_OPTIONS_ROLE);
        _grantRole(SET_EXTERNAL_ROLE, roles.setExternalAdmin);
        _grantRole(CRITICAL_FUNCTIONS_ROLE, roles.criticalFunctionsAdmin);
        _grantRole(SET_PROTOCOL_PARAMS_ROLE, roles.setProtocolParamsAdmin);
        _grantRole(SET_USDN_PARAMS_ROLE, roles.setUsdnParamsAdmin);
        _grantRole(SET_OPTIONS_ROLE, roles.setOptionsAdmin);

        // parameters
        s._minLeverage = 10 ** Constants.LEVERAGE_DECIMALS + 10 ** 12;
        s._maxLeverage = 10 * 10 ** Constants.LEVERAGE_DECIMALS;
        s._validationDeadline = 90 minutes;
        s._safetyMarginBps = 200; // 2%
        s._liquidationIteration = 1;
        s._protocolFeeBps = 800;
        s._rebalancerBonusBps = 8000; // 80%
        s._liquidationPenalty = 2; // 200 ticks -> ~2.02%
        s._EMAPeriod = 5 days;
        s._fundingSF = 12 * 10 ** (Constants.FUNDING_SF_DECIMALS - 2);
        s._feeThreshold = 1 ether;
        s._openExpoImbalanceLimitBps = 500;
        s._withdrawalExpoImbalanceLimitBps = 600;
        s._depositExpoImbalanceLimitBps = 500;
        s._closeExpoImbalanceLimitBps = 600;
        s._longImbalanceTargetBps = 550;
        s._positionFeeBps = 4; // 0.04%
        s._vaultFeeBps = 4; // 0.04%
        s._sdexBurnOnDepositRatio = 1e6; // 1%
        s._securityDepositValue = 0.5 ether;

        // Long positions
        s._EMA = int256(3 * 10 ** (Constants.FUNDING_RATE_DECIMALS - 4));

        // since all USDN must be minted by the protocol, we check that the total supply is 0
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }
        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        s._usdn = usdn;
        s._sdex = sdex;
        // those tokens should have 18 decimals
        if (usdn.decimals() != Constants.TOKENS_DECIMALS || sdex.decimals() != Constants.TOKENS_DECIMALS) {
            revert UsdnProtocolInvalidTokenDecimals();
        }

        s._usdnMinDivisor = usdn.MIN_DIVISOR();
        s._asset = asset;
        uint8 assetDecimals = asset.decimals();
        s._assetDecimals = assetDecimals;
        if (assetDecimals < Constants.FUNDING_SF_DECIMALS) {
            revert UsdnProtocolInvalidAssetDecimals(assetDecimals);
        }
        s._oracleMiddleware = oracleMiddleware;
        uint8 priceFeedDecimals = oracleMiddleware.getDecimals();
        s._priceFeedDecimals = priceFeedDecimals;
        s._liquidationRewardsManager = liquidationRewardsManager;
        s._tickSpacing = tickSpacing;
        s._feeCollector = feeCollector;

        s._targetUsdnPrice = uint128(10_087 * 10 ** (priceFeedDecimals - 4)); // $1.0087
        s._usdnRebaseThreshold = uint128(1009 * 10 ** (priceFeedDecimals - 3)); // $1.009
        s._minLongPosition = 2 * 10 ** assetDecimals;
    }

    /**
     * @notice Delegates the call to the setters contract
     * @param implementation The address of the setters contract
     */
    function _delegate(address implementation) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // TO DO : remove this function when the proxy is implemented
    function setSettersContract(address newUtilsContract) external {
        s._settersContract = newUtilsContract;
    }

    fallback() external {
        _delegate(s._settersContract);
    }
}
