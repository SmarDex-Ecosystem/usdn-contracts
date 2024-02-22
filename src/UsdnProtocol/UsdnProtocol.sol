// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import {
    PendingAction,
    VaultPendingAction,
    ProtocolAction,
    Position
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { UsdnProtocolActions } from "src/UsdnProtocol/UsdnProtocolActions.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

contract UsdnProtocol is IUsdnProtocol, UsdnProtocolActions, Ownable {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;

    /// @dev The minimum amount of wstETH for the initialization deposit and long.
    uint256 public constant MIN_INIT_DEPOSIT = 1 ether;

    /// @dev The amount of collateral for the first "dead" long position.
    uint128 public constant FIRST_LONG_AMOUNT = 1000;

    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation rewards manager contract.
     * @param tickSpacing The positions tick spacing.
     * @param feeCollector The address of the fee collector.
     */
    constructor(
        IUsdn usdn,
        IERC20Metadata asset,
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector
    )
        Ownable(msg.sender)
        UsdnProtocolStorage(usdn, asset, oracleMiddleware, liquidationRewardsManager, tickSpacing, feeCollector)
    { }

    /// @inheritdoc IUsdnProtocol
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable initializer {
        if (depositAmount < MIN_INIT_DEPOSIT) {
            revert UsdnProtocolMinInitAmount(MIN_INIT_DEPOSIT);
        }
        if (longAmount < MIN_INIT_DEPOSIT) {
            revert UsdnProtocolMinInitAmount(MIN_INIT_DEPOSIT);
        }
        // Since all USDN must be minted by the protocol, we check that the total supply is 0
        IUsdn usdn = _usdn;
        if (usdn.totalSupply() != 0) {
            revert UsdnProtocolInvalidUsdn(address(usdn));
        }

        // Create vault deposit
        PriceInfo memory currentPrice;
        {
            PendingAction memory pendingAction = _convertVaultPendingAction(
                VaultPendingAction({
                    action: ProtocolAction.ValidateDeposit,
                    timestamp: 0, // not needed since we have a special ProtocolAction for init
                    user: msg.sender,
                    _unused: 0, // unused
                    amount: depositAmount,
                    assetPrice: 0, // special case for init
                    totalExpo: 0,
                    balanceVault: 0,
                    balanceLong: 0,
                    usdnTotalSupply: 0
                })
            );

            // Transfer the wstETH for the deposit
            _asset.safeTransferFrom(msg.sender, address(this), depositAmount);

            emit InitiatedDeposit(msg.sender, depositAmount);
            // Mint USDN (a small amount is minted to the dead address)
            // last parameter = initializing
            currentPrice = _validateDepositWithAction(pendingAction, currentPriceData, true);
        }

        _lastUpdateTimestamp = uint40(block.timestamp);
        _lastPrice = currentPrice.price.toUint128();

        // Transfer the wstETH for the long
        _asset.safeTransferFrom(msg.sender, address(this), longAmount);

        // Create long positions with min leverage
        _createInitialPosition(DEAD_ADDRESS, FIRST_LONG_AMOUNT, currentPrice.price.toUint128(), minTick());
        _createInitialPosition(
            msg.sender,
            longAmount - FIRST_LONG_AMOUNT,
            currentPrice.price.toUint128(),
            getEffectiveTickForPrice(desiredLiqPrice) // no liquidation penalty
        );

        _refundExcessEther();
    }

    /// @inheritdoc IUsdnProtocol
    function setOracleMiddleware(IOracleMiddleware newOracleMiddleware) external onlyOwner {
        // check address zero middleware
        if (address(newOracleMiddleware) == address(0)) {
            revert UsdnProtocolZeroMiddlewareAddress();
        }
        _oracleMiddleware = newOracleMiddleware;
        emit OracleMiddlewareUpdated(address(_oracleMiddleware));
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationRewardsManager(address newLiquidationRewardsManager) external onlyOwner {
        if (newLiquidationRewardsManager == address(0)) {
            revert UsdnProtocolLiquidationRewardsManagerIsZeroAddress();
        }

        _liquidationRewardsManager = ILiquidationRewardsManager(newLiquidationRewardsManager);

        emit LiquidationRewardsManagerUpdated(newLiquidationRewardsManager);
    }

    /// @inheritdoc IUsdnProtocol
    function setMinLeverage(uint256 newMinLeverage) external onlyOwner {
        // zero minLeverage
        if (newMinLeverage == 0) {
            revert UsdnProtocolZeroMinLeverage();
        }

        // minLeverage greater or equal maxLeverage
        if (newMinLeverage >= _maxLeverage) {
            revert UsdnProtocolMinLeverageGreaterThanMax();
        }

        _minLeverage = newMinLeverage;
        emit MinLeverageUpdated(_minLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        // maxLeverage lower or equal minLeverage
        if (newMaxLeverage <= _minLeverage) {
            revert UsdnProtocolMaxLeverageLowerThanMin();
        }

        // maxLeverage greater than max 100
        if (newMaxLeverage > 100 * 10 ** LEVERAGE_DECIMALS) {
            revert UsdnProtocolMaxLeverageGreaterThanMax();
        }

        _maxLeverage = newMaxLeverage;
        emit MaxLeverageUpdated(_maxLeverage);
    }

    /// @inheritdoc IUsdnProtocol
    function setValidationDeadline(uint256 newValidationDeadline) external onlyOwner {
        // validation deadline lower than min 1 minute
        if (newValidationDeadline < 60) {
            revert UsdnProtocolValidationDeadlineLowerThanMin();
        }

        // validation deadline greater than max 1 year
        if (newValidationDeadline > 365 days) {
            revert UsdnProtocolValidationDeadlineGreaterThanMax();
        }

        _validationDeadline = newValidationDeadline;
        emit ValidationDeadlineUpdated(_validationDeadline);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationPenalty(uint24 newLiquidationPenalty) external onlyOwner {
        // liquidationPenalty greater than max 15
        if (newLiquidationPenalty > 15) {
            revert UsdnProtocolLiquidationPenaltyGreaterThanMax();
        }

        _liquidationPenalty = newLiquidationPenalty;
        emit LiquidationPenaltyUpdated(_liquidationPenalty);
    }

    /// @inheritdoc IUsdnProtocol
    function setSafetyMarginBps(uint256 newSafetyMarginBps) external onlyOwner {
        // safetyMarginBps greater than max 2000: 20%
        if (newSafetyMarginBps > 2000) {
            revert UsdnProtocolSafetyMarginBpsGreaterThanMax();
        }

        _safetyMarginBps = newSafetyMarginBps;
        emit SafetyMarginBpsUpdated(_safetyMarginBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setLiquidationIteration(uint16 newLiquidationIteration) external onlyOwner {
        // newLiquidationIteration greater than MAX_LIQUIDATION_ITERATION 10
        if (newLiquidationIteration > MAX_LIQUIDATION_ITERATION) {
            revert UsdnProtocolLiquidationIterationGreaterThanMax();
        }

        _liquidationIteration = newLiquidationIteration;
        emit LiquidationIterationUpdated(_liquidationIteration);
    }

    /// @inheritdoc IUsdnProtocol
    function setEMAPeriod(uint128 newEMAPeriod) external onlyOwner {
        // EMAPeriod is zero
        if (newEMAPeriod == 0) {
            revert UsdnProtocolZeroEMAPeriod();
        }

        // EMAPeriod is greater than max 3 months
        if (newEMAPeriod > 90 days) {
            revert UsdnProtocolEMAPeriodGreaterThanMax();
        }

        _EMAPeriod = newEMAPeriod;
        emit EMAPeriodUpdated(_EMAPeriod);
    }

    /// @inheritdoc IUsdnProtocol
    function setFundingSF(uint256 newFundingSF) external onlyOwner {
        // newFundingSF is zero
        if (newFundingSF == 0) {
            revert UsdnProtocolZeroFundingSF();
        }

        // newFundingSF is greater than max 1
        if (newFundingSF > 1000) {
            revert UsdnProtocolFundingSFGreaterThanMax();
        }

        _fundingSF = newFundingSF;
        emit FundingSFUpdated(_fundingSF);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeBps(uint16 protocolFeeBps) external onlyOwner {
        if (protocolFeeBps > BPS_DIVISOR) {
            revert UsdnProtocolInvalidProtocolFeeBps();
        }
        _protocolFeeBps = protocolFeeBps;
        emit FeeBpsUpdated(protocolFeeBps);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeThreshold(uint256 feeThreshold) external onlyOwner {
        _feeThreshold = feeThreshold;
        emit FeeThresholdUpdated(feeThreshold);
    }

    /// @inheritdoc IUsdnProtocol
    function setFeeCollector(address feeCollector) external onlyOwner {
        if (feeCollector == address(0)) {
            revert UsdnProtocolInvalidFeeCollector();
        }
        _feeCollector = feeCollector;
        emit FeeCollectorUpdated(feeCollector);
    }

    function _createInitialPosition(address user, uint128 amount, uint128 price, int24 tick) internal {
        uint128 liquidationPrice = getEffectivePriceForTick(tick);
        uint128 leverage = _getLeverage(price, liquidationPrice);
        Position memory long =
            Position({ user: user, amount: amount, leverage: leverage, timestamp: uint40(block.timestamp) });
        // Save the position and update the state
        (uint256 tickVersion, uint256 index) = _saveNewPosition(tick, long);
        emit InitiatedOpenPosition(user, long.timestamp, long.leverage, long.amount, price, tick, tickVersion, index);
        emit ValidatedOpenPosition(user, long.leverage, price, tick, tickVersion, index);
    }
}
