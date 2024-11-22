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
    function initializeStorage(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        IUsdnProtocolFallback protocolFallback
    ) public initializer {
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

        // parameters
        s._minLeverage = 10 ** Constants.LEVERAGE_DECIMALS + 10 ** (Constants.LEVERAGE_DECIMALS - 1); // x1.1
        s._maxLeverage = 10 * 10 ** Constants.LEVERAGE_DECIMALS; // x10
        s._lowLatencyValidatorDeadline = 15 minutes;
        s._onChainValidatorDeadline = 65 minutes; // slightly more than chainlink's heartbeat
        s._safetyMarginBps = 200; // 2%
        s._liquidationIteration = 1;
        s._protocolFeeBps = 800; // 8%
        s._rebalancerBonusBps = 8000; // 80%
        s._liquidationPenalty = 200; // 200 ticks -> ~2.02%
        s._EMAPeriod = 5 days;
        s._fundingSF = 12 * 10 ** (Constants.FUNDING_SF_DECIMALS - 2); // 0.12
        s._feeThreshold = 1 ether;
        s._openExpoImbalanceLimitBps = 500; // 5%
        s._withdrawalExpoImbalanceLimitBps = 600; // 6%
        s._depositExpoImbalanceLimitBps = 500; // 5%
        s._closeExpoImbalanceLimitBps = 600; // 6%
        s._rebalancerCloseExpoImbalanceLimitBps = 350; // 3.5%
        s._longImbalanceTargetBps = 400; // 4%
        s._positionFeeBps = 4; // 0.04%
        s._vaultFeeBps = 4; // 0.04%
        s._sdexBurnOnDepositRatio = 1e6; // 1%
        s._securityDepositValue = 0.5 ether;
        s._removeBlockedPendingActionsDelay = 10 minutes;

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
        s._minLongPosition = 2 * 10 ** assetDecimals; // 2 tokens
        s._protocolFallbackAddr = address(protocolFallback);
    }

    /**
     * @inheritdoc UUPSUpgradeable
     * @notice Function to verify that the caller to upgrade the protocol is authorized
     * @param implementation The address of the new implementation
     */
    function _authorizeUpgrade(address implementation) internal override onlyRole(Constants.PROXY_UPGRADE_ROLE) { }

    /**
     * @notice Delegates the call to the fallback contract
     * @param protocolFallbackAddr The address of the fallback contract
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

    fallback() external {
        _delegate(Utils._getMainStorage()._protocolFallbackAddr);
    }
}
