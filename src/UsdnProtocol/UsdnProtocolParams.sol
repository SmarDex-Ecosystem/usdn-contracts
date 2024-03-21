// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolParams } from "src/interfaces/UsdnProtocol/IUsdnProtocolParams.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";

contract UsdnProtocolParams is IUsdnProtocolParams, Ownable {
    /* -------------------------------------------------------------------------- */
    /*                          Constants and immutables                          */
    /* -------------------------------------------------------------------------- */

    uint256 public constant BPS_DIVISOR = 10_000;

    /* -------------------------------------------------------------------------- */
    /*                              Pseudo-constants                              */
    /* -------------------------------------------------------------------------- */

    IUsdnProtocol internal _protocol;

    uint8 internal _leverageDecimals;

    uint8 internal _fundingSfDecimals;

    uint8 internal _priceFeedDecimals;

    uint16 internal _maxLiquidationIteration;

    /* -------------------------------------------------------------------------- */
    /*                                    State                                   */
    /* -------------------------------------------------------------------------- */

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

    /// @notice The position fee in basis point
    uint16 internal _positionFeeBps = 4; // 0.04%

    /// @notice The nominal (target) price of USDN (with _priceFeedDecimals)
    uint128 internal _targetUsdnPrice;

    /// @notice The USDN price threshold to trigger a rebase (with _priceFeedDecimals)
    uint128 internal _usdnRebaseThreshold;

    /**
     * @notice The interval between two automatic rebase checks
     * @dev A rebase can be forced (if the `_usdnRebaseThreshold` is exceeded) by calling the `liquidate` function
     */
    uint256 internal _usdnRebaseInterval = 12 hours;

    /* -------------------------------------------------------------------------- */
    /*                               Initialization                               */
    /* -------------------------------------------------------------------------- */

    constructor() Ownable(msg.sender) { }

    /**
     * @notice Constructor.
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param feeCollector The address of the fee collector.
     */
    function initialize(
        IUsdnProtocol protocol,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        address feeCollector,
        uint8 leverageDecimals,
        uint8 fundingSfDecimals,
        uint8 priceFeedDecimals,
        uint16 maxLiquidationIteration
    ) external {
        if (_initialized) {
            revert UsdnProtocolParamsAlreadyInitialized();
        }
        _initialized = true;

        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }

        _protocol = protocol;
        _leverageDecimals = leverageDecimals;
        _fundingSfDecimals = fundingSfDecimals;
        _priceFeedDecimals = priceFeedDecimals;
        _maxLiquidationIteration = maxLiquidationIteration;

        _oracleMiddleware = oracleMiddleware;
        _liquidationRewardsManager = liquidationRewardsManager;
        _feeCollector = feeCollector;

        _minLeverage = 10 ** leverageDecimals + 10 ** (leverageDecimals - 9); // 1.000000001x
        _maxLeverage = 10 * 10 ** leverageDecimals; // 10x
        _fundingSF = 12 * 10 ** (fundingSfDecimals - 2); // 0.12

        _targetUsdnPrice = uint128(102 * 10 ** (priceFeedDecimals - 2)); // $1.02
        _usdnRebaseThreshold = uint128(1021 * 10 ** (priceFeedDecimals - 3)); // $1.021
    }

    /* -------------------------------------------------------------------------- */
    /*                          Pseudo-constants getters                          */
    /* -------------------------------------------------------------------------- */

    function getProtocol() external view returns (IUsdnProtocol) {
        return _protocol;
    }

    function getLeverageDecimals() external view returns (uint8) {
        return _leverageDecimals;
    }

    function getFundingSfDecimals() external view returns (uint8) {
        return _fundingSfDecimals;
    }

    function getPriceFeedDecimals() external view returns (uint8) {
        return _priceFeedDecimals;
    }

    function getMaxLiquidationIteration() external view returns (uint16) {
        return _maxLiquidationIteration;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters getters                         */
    /* -------------------------------------------------------------------------- */

    function getOracleMiddleware() external view returns (IOracleMiddleware) {
        return _oracleMiddleware;
    }

    function getLiquidationRewardsManager() external view returns (ILiquidationRewardsManager) {
        return _liquidationRewardsManager;
    }

    function getMinLeverage() external view returns (uint256) {
        return _minLeverage;
    }

    function getMaxLeverage() external view returns (uint256) {
        return _maxLeverage;
    }

    function getValidationDeadline() external view returns (uint256) {
        return _validationDeadline;
    }

    function getLiquidationPenalty() external view returns (uint24) {
        return _liquidationPenalty;
    }

    function getSafetyMarginBps() external view returns (uint256) {
        return _safetyMarginBps;
    }

    function getLiquidationIteration() external view returns (uint16) {
        return _liquidationIteration;
    }

    function getEMAPeriod() external view returns (uint128) {
        return _EMAPeriod;
    }

    function getFundingSF() external view returns (uint256) {
        return _fundingSF;
    }

    function getProtocolFeeBps() external view returns (uint16) {
        return _protocolFeeBps;
    }

    function getPositionFeeBps() external view returns (uint16) {
        return _positionFeeBps;
    }

    function getFeeThreshold() external view returns (uint256) {
        return _feeThreshold;
    }

    function getFeeCollector() external view returns (address) {
        return _feeCollector;
    }

    function getMiddlewareValidationDelay() external view returns (uint256) {
        return _oracleMiddleware.getValidationDelay();
    }

    function getTargetUsdnPrice() external view returns (uint128) {
        return _targetUsdnPrice;
    }

    function getUsdnRebaseThreshold() external view returns (uint128) {
        return _usdnRebaseThreshold;
    }

    function getUsdnRebaseInterval() external view returns (uint256) {
        return _usdnRebaseInterval;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external onlyOwner {
        // check address zero middleware
        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolInvalidMiddlewareAddress();
        }
        _oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(newOracleMiddleware));
    }

    function setLiquidationRewardsManager(ILiquidationRewardsManager newLiquidationRewardsManager) external onlyOwner {
        if (address(newLiquidationRewardsManager) == address(0)) {
            revert UsdnProtocolInvalidLiquidationRewardsManagerAddress();
        }

        _liquidationRewardsManager = newLiquidationRewardsManager;

        emit LiquidationRewardsManagerUpdated(address(newLiquidationRewardsManager));
    }

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

    function setLiquidationPenalty(uint24 newLiquidationPenalty) external onlyOwner {
        // liquidationPenalty greater than max 15
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolInvalidLiquidationPenalty();
        }

        _liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(newLiquidationPenalty);
    }

    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than max 2000: 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolInvalidSafetyMarginBps();
        }

        _safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(newSafetyMarginBps);
    }

    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        // newLiquidationIteration greater than _maxLiquidationIteration
        if (newLiquidationIteration > _maxLiquidationIteration) {
            revert UsdnProtocolInvalidLiquidationIteration();
        }

        _liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(newLiquidationIteration);
    }

    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        // EMAPeriod is greater than max 3 months
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolInvalidEMAPeriod();
        }

        _EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(newEMAPeriod);
    }

    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        // newFundingSF is greater than max
        if (newFundingSF > 10 ** _fundingSfDecimals) {
            revert UsdnProtocolInvalidFundingSF();
        }

        _fundingSF = newFundingSF;
        emit FundingSFUpdated(newFundingSF);
    }

    function setProtocolFeeBps(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > BPS_DIVISOR) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        _protocolFeeBps = newProtocolFeeBps;
        emit FeeBpsUpdated(newProtocolFeeBps);
    }

    function setPositionFeeBps(uint16 newPositionFee) external onlyOwner {
        // newPositionFee greater than max 2000: 20%
        if (newPositionFee > 2000) {
            revert UsdnProtocolInvalidPositionFee();
        }
        _positionFeeBps = newPositionFee;
        emit PositionFeeUpdated(newPositionFee);
    }

    function setFeeThreshold(uint256 newFeeThreshold) external onlyOwner {
        _feeThreshold = newFeeThreshold;
        emit FeeThresholdUpdated(newFeeThreshold);
    }

    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        _feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

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

    function setUsdnRebaseThreshold(uint128 newThreshold) external onlyOwner {
        if (newThreshold < _targetUsdnPrice) {
            revert UsdnProtocolInvalidUsdnRebaseThreshold();
        }
        _usdnRebaseThreshold = newThreshold;
        emit UsdnRebaseThresholdUpdated(newThreshold);
    }

    function setUsdnRebaseInterval(uint256 newInterval) external onlyOwner {
        _usdnRebaseInterval = newInterval;
        emit UsdnRebaseIntervalUpdated(newInterval);
    }
}
