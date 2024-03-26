// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolParams } from "src/interfaces/UsdnProtocol/IUsdnProtocolParams.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

contract UsdnProtocolParams is IUsdnProtocolParams, Ownable {
    using SafeCast for uint256;

    /* -------------------------------------------------------------------------- */
    /*                          Constants and immutables                          */
    /* -------------------------------------------------------------------------- */

    uint256 public constant BPS_DIVISOR = 10_000;

    /* -------------------------------------------------------------------------- */
    /*                              Pseudo-constants                              */
    /* -------------------------------------------------------------------------- */

    uint8 internal _leverageDecimals;

    uint8 internal _fundingSfDecimals;

    uint8 internal _priceFeedDecimals;

    uint16 internal _maxLiquidationIteration;

    uint128 internal _securityDepositFactor;

    /* -------------------------------------------------------------------------- */
    /*                                    State                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Whether the contract was already initialized
    bool internal _initialized;

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The oracle middleware contract.
    IOracleMiddleware internal _oracleMiddleware;

    /// @notice The liquidation rewards manager contract.
    ILiquidationRewardsManager internal _liquidationRewardsManager;

    /// @notice The minimum leverage for a position
    uint256 internal _minLeverage;

    /// @notice The maximum leverage for a position
    uint256 internal _maxLeverage;

    /// @notice The deadline for a user to confirm their own action
    uint256 internal _validationDeadline = 20 minutes;

    /// @notice The liquidation penalty (in tick spacing units)
    uint24 internal _liquidationPenalty = 2; // 200 ticks -> ~2.02%

    /// @notice Safety margin for the liquidation price of newly open positions, in basis points
    uint256 internal _safetyMarginBps = 200; // 2%

    /// @notice User current liquidation iteration in tick.
    uint16 internal _liquidationIteration = 3;

    /// @notice The moving average period of the funding rate
    uint128 internal _EMAPeriod = 5 days;

    /// @notice The scaling factor (SF) of the funding rate (0.12)
    uint256 internal _fundingSF;

    /// @notice The protocol fee percentage (in bps)
    uint16 internal _protocolFeeBps = 10;

    /// @notice The fee collector's address
    address internal _feeCollector;

    /// @notice The fee threshold above which fee will be sent
    uint256 internal _feeThreshold = 1 ether;

    /**
     * @notice The imbalance limit of the long expo for open actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of long
     * the open rebalancing mechanism is triggered, preventing the opening of a new long position.
     */
    int256 internal _openExpoImbalanceLimitBps = 200;

    /**
     * @notice The imbalance limit of the long expo for withdrawal actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of long,
     * the withdrawal rebalancing mechanism is triggered, preventing the withdraw of existing vault position.
     */
    int256 internal _withdrawalExpoImbalanceLimitBps = 600;

    /**
     * @notice The imbalance limit of the vault expo for deposit actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of vault,
     * the deposit vault rebalancing mechanism is triggered, preventing the opening of new vault position.
     */
    int256 internal _depositExpoImbalanceLimitBps = 200;

    /**
     * @notice The imbalance limit of the vault expo for close actions (in basis points).
     * @dev As soon as the difference between vault expo and long expo exceeds this basis point limit in favor of vault,
     * the withdrawal vault rebalancing mechanism is triggered, preventing the close of existing long position.
     */
    int256 internal _closeExpoImbalanceLimitBps = 600;

    /// @notice The position fee in basis point
    uint16 internal _positionFeeBps = 4; // 0.04%

    /// @notice The deposit required for a new position (0.5 ether)
    uint256 internal _securityDepositValue = 0.5 ether;

    /// @notice The nominal (target) price of USDN (with _priceFeedDecimals)
    uint128 internal _targetUsdnPrice;

    /// @notice The USDN price threshold to trigger a rebase (with _priceFeedDecimals)
    uint128 internal _usdnRebaseThreshold;

    /**
     * @notice The interval between two automatic rebase checks. Disabled by default
     * @dev A rebase can be forced (if the `_usdnRebaseThreshold` is exceeded) by calling the `liquidate` function
     */
    uint256 internal _usdnRebaseInterval = 0;

    /* -------------------------------------------------------------------------- */
    /*                               Initialization                               */
    /* -------------------------------------------------------------------------- */

    constructor() Ownable(msg.sender) { }

    function initialize(
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        address feeCollector,
        uint8 leverageDecimals,
        uint8 fundingSfDecimals,
        uint8 priceFeedDecimals,
        uint16 maxLiquidationIteration,
        uint128 securityDepositFactor
    ) external {
        if (_initialized) {
            revert UsdnProtocolParamsAlreadyInitialized();
        }
        _initialized = true;

        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        _leverageDecimals = leverageDecimals;
        _fundingSfDecimals = fundingSfDecimals;
        _priceFeedDecimals = priceFeedDecimals;
        _maxLiquidationIteration = maxLiquidationIteration;
        _securityDepositFactor = securityDepositFactor;

        _oracleMiddleware = oracleMiddleware;
        _liquidationRewardsManager = liquidationRewardsManager;
        _feeCollector = feeCollector;

        _minLeverage = 10 ** leverageDecimals + 10 ** (leverageDecimals - 9); // 1.000000001x
        _maxLeverage = 10 * 10 ** leverageDecimals; // 10x
        _fundingSF = 12 * 10 ** (fundingSfDecimals - 2); // 0.12

        _targetUsdnPrice = uint128(1005 * 10 ** (_priceFeedDecimals - 3)); // $1.005
        _usdnRebaseThreshold = uint128(1009 * 10 ** (_priceFeedDecimals - 3)); // $1.009
    }

    /* -------------------------------------------------------------------------- */
    /*                          Pseudo-constants getters                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolParams
    function getLeverageDecimals() external view returns (uint8) {
        return _leverageDecimals;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getFundingSfDecimals() external view returns (uint8) {
        return _fundingSfDecimals;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getPriceFeedDecimals() external view returns (uint8) {
        return _priceFeedDecimals;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getMaxLiquidationIteration() external view returns (uint16) {
        return _maxLiquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getSecurityDepositFactor() external view returns (uint128) {
        return _securityDepositFactor;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolParams
    function getOracleMiddleware() external view returns (IOracleMiddleware) {
        return _oracleMiddleware;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager) {
        return _liquidationRewardsManager;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getMinLeverage() external view returns (uint256) {
        return _minLeverage;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getMaxLeverage() external view returns (uint256) {
        return _maxLeverage;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getValidationDeadline() external view returns (uint256) {
        return _validationDeadline;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getLiquidationPenalty() external view returns (uint24) {
        return _liquidationPenalty;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getSafetyMarginBps() external view returns (uint256) {
        return _safetyMarginBps;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getLiquidationIteration() external view returns (uint16) {
        return _liquidationIteration;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getEMAPeriod() external view returns (uint128) {
        return _EMAPeriod;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getFundingSF() external view returns (uint256) {
        return _fundingSF;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getProtocolFeeBps() external view returns (uint16) {
        return _protocolFeeBps;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getPositionFeeBps() external view returns (uint16) {
        return _positionFeeBps;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getSecurityDepositValue() external view returns (uint256) {
        return _securityDepositValue;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getFeeThreshold() external view returns (uint256) {
        return _feeThreshold;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getFeeCollector() external view returns (address) {
        return _feeCollector;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getMiddlewareValidationDelay() external view returns (uint256) {
        return _oracleMiddleware.getValidationDelay();
    }

    /// @inheritdoc IUsdnProtocolParams
    function getTargetUsdnPrice() external view returns (uint128) {
        return _targetUsdnPrice;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getUsdnRebaseThreshold() external view returns (uint128) {
        return _usdnRebaseThreshold;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getUsdnRebaseInterval() external view returns (uint256) {
        return _usdnRebaseInterval;
    }

    /// @inheritdoc IUsdnProtocolParams
    function getExpoImbalanceLimits()
        external
        view
        returns (
            int256 openExpoImbalanceLimitBps_,
            int256 depositExpoImbalanceLimitBps_,
            int256 withdrawalExpoImbalanceLimitBps_,
            int256 closeExpoImbalanceLimitBps_
        )
    {
        return (
            _openExpoImbalanceLimitBps,
            _depositExpoImbalanceLimitBps,
            _withdrawalExpoImbalanceLimitBps,
            _closeExpoImbalanceLimitBps
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdnProtocolParams
    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external onlyOwner {
        // check address zero middleware
        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolInvalidMiddlewareAddress();
        }
        _oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    /// @inheritdoc IUsdnProtocolParams
    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external onlyOwner {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        _liquidationRewardsManager = newLiquidationRewardsManager;

        emit LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

    /// @inheritdoc IUsdnProtocolParams
    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        // zero minLeverage
        if (newMinLeverage <= 10 ** _leverageDecimals) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        // minLeverage greater or equal maxLeverage
        if (newMinLeverage >= _maxLeverage) {
            revert UsdnProtocolInvalidMinLeverage();
        }

        _minLeverage = newMinLeverage;
        emit MinLeverageUpdated(newMinLeverage);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        // maxLeverage lower or equal minLeverage
        if (newMaxLeverage <= _minLeverage) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        // maxLeverage greater than max 100
        if (newMaxLeverage > 100 * 10 ** _leverageDecimals) {
            revert UsdnProtocolInvalidMaxLeverage();
        }

        _maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        // validation deadline lower than min 1 minute
        if (newValidationDeadline < 60) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        // validation deadline greater than max 1 day
        if (newValidationDeadline > 1 days) {
            revert UsdnProtocolInvalidValidationDeadline();
        }

        _validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(newValidationDeadline);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external onlyOwner {
        // liquidationPenalty greater than max 15
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        _liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than max 2000: 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        _safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        // newLiquidationIteration greater than _maxLiquidationIteration
        if (newLiquidationIteration > _maxLiquidationIteration) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        _liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        // EMAPeriod is greater than max 3 months
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        _EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        // newFundingSF is greater than max
        if (newFundingSF > 10 ** _fundingSfDecimals) {
            revert UsdnProtocolInvalidFundingSF();
        }

        _fundingSF = newFundingSF;
        emit FundingSFUpdated(newFundingSF);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > BPS_DIVISOR) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        _protocolFeeBps = newProtocolFeeBps;
        emit FeeBpsUpdated(newProtocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setPositionFeeBps(uint16 newPositionFee) external onlyOwner {
        // newPositionFee greater than max 2000: 20%
        if (newPositionFee > 2000) {
            revert UsdnProtocolInvalidPositionFee();
        }
        _positionFeeBps = newPositionFee;
        emit PositionFeeUpdated(newPositionFee);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setSecurityDepositValue(uint256 securityDepositValue) external onlyOwner {
        // we allow to set the security deposit between 10 ** 15 (0.001 ether) and 10 ethers
        // the value must be a multiple of the SECURITY_DEPOSIT_FACTOR
        if (securityDepositValue > 10 ether || securityDepositValue % _securityDepositFactor != 0) {
            revert UsdnProtocolInvalidSecurityDepositValue();
        }

        _securityDepositValue = securityDepositValue;
        emit SecurityDepositValueUpdated(securityDepositValue);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setFeeThreshold(uint256 newFeeThreshold) external onlyOwner {
        _feeThreshold = newFeeThreshold;
        emit FeeThresholdUpdated(newFeeThreshold);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        _feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setTargetUsdnPrice(uint128 newPrice) external onlyOwner {
        if (newPrice > _usdnRebaseThreshold) {
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        if (newPrice < uint128(10 ** _priceFeedDecimals)) {
            // values smaller than $1 are not allowed
            revert UsdnProtocolInvalidTargetUsdnPrice();
        }
        _targetUsdnPrice = newPrice;
        emit TargetUsdnPriceUpdated(newPrice);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyOwner {
        if (newThreshold < _targetUsdnPrice) {
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        _usdnRebaseThreshold = newThreshold;
        emit UsdnRebaseThresholdUpdated(newThreshold);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setUsdnRebaseInterval(uint256 newInterval) external onlyOwner {
        _usdnRebaseInterval = newInterval;
        emit UsdnRebaseIntervalUpdated(newInterval);
    }

    /// @inheritdoc IUsdnProtocolParams
    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps
    ) external onlyOwner {
        _openExpoImbalanceLimitBps = newOpenLimitBps.toInt256();
        _depositExpoImbalanceLimitBps = newDepositLimitBps.toInt256();

        if (newWithdrawalLimitBps != 0 && newWithdrawalLimitBps < newOpenLimitBps) {
            // withdrawal limit lower than open not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        _withdrawalExpoImbalanceLimitBps = newWithdrawalLimitBps.toInt256();

        if (newCloseLimitBps != 0 && newCloseLimitBps < newDepositLimitBps) {
            // close limit lower than deposit not permitted
            revert UsdnProtocolInvalidExpoImbalanceLimit();
        }
        _closeExpoImbalanceLimitBps = newCloseLimitBps.toInt256();

        emit ImbalanceLimitsUpdated(newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps);
    }
}
