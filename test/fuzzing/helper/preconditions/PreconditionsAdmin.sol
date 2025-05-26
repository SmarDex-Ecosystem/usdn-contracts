// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PreconditionsBase } from "./PreconditionsBase.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol//libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

abstract contract PreconditionsAdmin is PreconditionsBase {
    enum PriceMode {
        NORMAL,
        ANTI_LIQUIDATION,
        SWING
    }

    struct SetPricePreconditions {
        int256 currentPrice;
        int256 newPrice;
        int256 minAllowedPrice;
        int256 maxAllowedPrice;
    }

    PriceMode internal currentMode = PriceMode.NORMAL;
    uint256 internal swingModeCallCount = 0;

    function setPriceMode() internal {
        if (usdnProtocol.checkNumOfPositions() < 7) {
            currentMode = PriceMode.ANTI_LIQUIDATION;
        } else {
            currentMode = PriceMode.SWING;
        }
    }

    function setPricePreconditions(int256 priceChangePercent) internal returns (SetPricePreconditions memory) {
        setPriceMode();

        (, int256 currentPrice,,,) = chainlink.latestRoundData();
        currentPrice = currentPrice / int256(10 ** chainlink.decimals());

        int256 maxChangePercent = INT_MAX_CHANGE_BP;
        int256 newPrice;

        if (currentMode == PriceMode.SWING) {
            swingModeCallCount++;
            if (swingModeCallCount % 10 == 0) {
                // Large swing every 10 calls, currently 3%
                maxChangePercent = SWING_MODE_LARGE_MAX_CHANGE;
            } else {
                // Normal swing for other calls, 10%
                maxChangePercent = SWING_MODE_NORMAL_MAX_CHANGE;
            }
        }

        int256 clampedChangePercent = fl.clamp(priceChangePercent, -maxChangePercent, maxChangePercent);

        int256 priceChange = (currentPrice * clampedChangePercent) / INT_ONE_HUNDRED_BP;

        newPrice = currentPrice + priceChange;

        if (newPrice < MIN_ORACLE_PRICE) {
            newPrice = MIN_ORACLE_PRICE;
        }

        if (currentMode == PriceMode.ANTI_LIQUIDATION && newPrice < int256(uint256(initialLongPositionPrice)) / 1e18) {
            newPrice = int256(uint256(initialLongPositionPrice + 1e18) / 1e18);
        }

        int256 minAllowedPrice = (currentPrice * (INT_ONE_HUNDRED_BP - maxChangePercent)) / INT_ONE_HUNDRED_BP;
        int256 maxAllowedPrice = (currentPrice * (INT_ONE_HUNDRED_BP + maxChangePercent)) / INT_ONE_HUNDRED_BP;

        if (currentMode == PriceMode.SWING) { }

        return SetPricePreconditions({
            currentPrice: currentPrice,
            newPrice: newPrice,
            minAllowedPrice: minAllowedPrice,
            maxAllowedPrice: maxAllowedPrice
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                                USDN Protocol                               */
    /* -------------------------------------------------------------------------- */

    function setValidationsDeadlinesPreconditions(uint256 seed)
        internal
        view
        returns (uint128 lowLatencyDeadline, uint128 onChainDeadline)
    {
        uint256 seed1 = uint128(seed); // Lower 128 bits
        uint256 seed2 = uint128(seed >> 128); // Upper 128 bits
        uint16 delay = usdnProtocol.getValidatorDeadlines();

        lowLatencyDeadline = uint128(bound(seed1, Constants.MIN_VALIDATION_DEADLINE, delay));
        onChainDeadline = uint128(bound(seed2, 0, Constants.MAX_VALIDATION_DEADLINE));
    }

    function setMinLeveragePreconditions(uint256 seed) internal view returns (uint256 minLeverage) {
        uint256 maxBound = usdnProtocol.getMinLeverage();
        uint256 minBound = 10 ** Constants.LEVERAGE_DECIMALS + 10 ** (Constants.LEVERAGE_DECIMALS - 1); // x1.1
        minLeverage = bound(seed, minBound, maxBound);
    }

    function setMaxLeveragePreconditions(uint256 seed) internal view returns (uint256 maxLeverage) {
        uint256 minBound = usdnProtocol.getMaxLeverage();
        maxLeverage = bound(seed, minBound, Constants.MAX_LEVERAGE);
    }

    function setLiquidationPenaltyPreconditions(uint256 seed) internal pure returns (uint24 liquidationPenalty) {
        liquidationPenalty = uint24(bound(seed, 0, Constants.MAX_LIQUIDATION_PENALTY));
    }

    function setEMAPeriodPreconditions(uint256 seed) internal pure returns (uint128 emaPeriod) {
        emaPeriod = uint128(bound(seed, 0, Constants.MAX_EMA_PERIOD));
    }

    function setFundingSFPreconditions(uint256 seed) internal pure returns (uint256 fundingSF) {
        fundingSF = bound(seed, 0, 10 ** Constants.FUNDING_SF_DECIMALS);
    }

    function setProtocolFeeBpsPreconditions(uint256 seed) internal pure returns (uint16 protocolFeeBps) {
        protocolFeeBps = uint16(bound(seed, 0, Constants.MAX_PROTOCOL_FEE_BPS));
    }

    function setPositionFeeBpsPreconditions(uint256 seed) internal pure returns (uint16 positionFee) {
        positionFee = uint16(bound(seed, 0, Constants.MAX_POSITION_FEE_BPS));
    }

    function setVaultFeeBpsPreconditions(uint256 seed) internal pure returns (uint16 vaultFee) {
        vaultFee = uint16(bound(seed, 0, Constants.MAX_VAULT_FEE_BPS));
    }

    function setSdexRewardsRatioBpsPreconditions(uint256 seed) internal returns (uint16 rewards) {
        rewards = uint16(bound(seed, 0, Constants.MAX_SDEX_REWARDS_RATIO_BPS));
    }

    function setRebalancerBonusBpsPreconditions(uint256 seed) internal returns (uint16 bonus) {
        bonus = uint16(bound(seed, 0, Constants.BPS_DIVISOR));
    }

    function setSdexBurnOnDepositRatioPreconditions(uint256 seed) internal returns (uint32 ratio) {
        uint256 minBound = 1e6;
        ratio = uint32(bound(seed, minBound, MAX_SDEX_BURN_RATIO));
    }

    function setSecurityDepositValuePreconditions(uint256 seed) internal returns (uint64 securityDeposit) {
        securityDeposit = uint64(bound(seed, 1 ether, Constants.MAX_SECURITY_DEPOSIT));
    }

    function setExpoImbalanceLimitsPreconditions(uint256 seed)
        internal
        returns (
            uint256 openLimit,
            uint256 depositLimit,
            uint256 withdrawalLimit,
            uint256 closeLimit,
            uint256 rebalancerCloseLimit,
            int256 longImbalanceTarget
        )
    {
        uint256 parameterToModify = seed % 6;
        return _getModifiedLimits(parameterToModify, seed);
    }

    /**
     * @dev Get current limits and modify one based on the seed
     */
    function _getModifiedLimits(uint256 parameterToModify, uint256 seed)
        private
        view
        returns (
            uint256 openLimit,
            uint256 depositLimit,
            uint256 withdrawalLimit,
            uint256 closeLimit,
            uint256 rebalancerCloseLimit,
            int256 longImbalanceTarget
        )
    {
        Types.Storage storage s = Utils._getMainStorage();
        int256 openExpoImbalanceLimitBps = s._openExpoImbalanceLimitBps;
        int256 depositExpoImbalanceLimitBps = s._depositExpoImbalanceLimitBps;
        int256 withdrawalExpoImbalanceLimitBps = s._withdrawalExpoImbalanceLimitBps;
        int256 closeExpoImbalanceLimitBps = s._closeExpoImbalanceLimitBps;
        int256 rebalancerCloseExpoImbalanceLimitBps = s._rebalancerCloseExpoImbalanceLimitBps;
        int256 longImbalanceTargetBps = s._longImbalanceTargetBps;

        (
            openExpoImbalanceLimitBps,
            depositExpoImbalanceLimitBps,
            withdrawalExpoImbalanceLimitBps,
            closeExpoImbalanceLimitBps,
            rebalancerCloseExpoImbalanceLimitBps,
            longImbalanceTargetBps
        ) = _modifyOneLimitOnly(
            parameterToModify,
            seed,
            openExpoImbalanceLimitBps,
            depositExpoImbalanceLimitBps,
            withdrawalExpoImbalanceLimitBps,
            closeExpoImbalanceLimitBps,
            rebalancerCloseExpoImbalanceLimitBps,
            longImbalanceTargetBps
        );

        return (
            uint256(openExpoImbalanceLimitBps),
            uint256(depositExpoImbalanceLimitBps),
            uint256(withdrawalExpoImbalanceLimitBps),
            uint256(closeExpoImbalanceLimitBps),
            uint256(rebalancerCloseExpoImbalanceLimitBps),
            longImbalanceTargetBps
        );
    }

    /**
     * @dev Modifies a single limit based on parameterToModify
     */
    function _modifyOneLimitOnly(
        uint256 parameterToModify,
        uint256 seed,
        int256 openExpoImbalanceLimitBps,
        int256 depositExpoImbalanceLimitBps,
        int256 withdrawalExpoImbalanceLimitBps,
        int256 closeExpoImbalanceLimitBps,
        int256 rebalancerCloseExpoImbalanceLimitBps,
        int256 longImbalanceTargetBps
    ) private pure returns (int256, int256, int256, int256, int256, int256) {
        if (parameterToModify == 0) {
            // Modify openExpoImbalanceLimitBps
            // min = 0 and max = withdrawalExpoImbalanceLimitBps
            openExpoImbalanceLimitBps = int256(bound(seed, 0, uint256(withdrawalExpoImbalanceLimitBps)));
        } else if (parameterToModify == 1) {
            // Modify depositExpoImbalanceLimitBps
            // min = 0 and max = closeExpoImbalanceLimitBps
            depositExpoImbalanceLimitBps = int256(bound(seed, 0, uint256(closeExpoImbalanceLimitBps)));
        } else if (parameterToModify == 2) {
            // Modify withdrawalExpoImbalanceLimitBps
            // if != 0, min = openExpoImbalanceLimitBps and max = 100%
            if (withdrawalExpoImbalanceLimitBps != 0) {
                withdrawalExpoImbalanceLimitBps =
                    int256(bound(seed, uint256(openExpoImbalanceLimitBps), Constants.BPS_DIVISOR));
            }
        } else if (parameterToModify == 3) {
            // Modify closeExpoImbalanceLimitBps
            // if != 0, min = max(depositExpoImbalanceLimitBps, longImbalanceTargetBps,
            // rebalancerCloseExpoImbalanceLimitBps)
            // and max = 100%
            if (closeExpoImbalanceLimitBps != 0) {
                uint256 min = depositExpoImbalanceLimitBps > longImbalanceTargetBps
                    ? uint256(depositExpoImbalanceLimitBps)
                    : uint256(longImbalanceTargetBps);
                min = rebalancerCloseExpoImbalanceLimitBps > int256(min)
                    ? uint256(rebalancerCloseExpoImbalanceLimitBps)
                    : min;

                closeExpoImbalanceLimitBps = int256(bound(seed, min, Constants.BPS_DIVISOR));
            }
        } else if (parameterToModify == 4) {
            // Modify rebalancerCloseExpoImbalanceLimitBps
            // if != 0, min = 1 (0.01%) and max = closeExpoImbalanceLimitBps
            if (rebalancerCloseExpoImbalanceLimitBps != 0) {
                rebalancerCloseExpoImbalanceLimitBps =
                    int256(bound(seed, 1, longImbalanceTargetBps > 0 ? uint256(longImbalanceTargetBps - 1) : 1));
            }
        } else if (parameterToModify == 5) {
            // Modify longImbalanceTargetBps
            // min = max(-50%, -withdrawalExpoImbalanceLimitBps) and max = closeExpoImbalanceLimitBps
            int256 min = -int256(Constants.BPS_DIVISOR / 2) > -withdrawalExpoImbalanceLimitBps
                ? -int256(Constants.BPS_DIVISOR / 2)
                : -withdrawalExpoImbalanceLimitBps;

            if (rebalancerCloseExpoImbalanceLimitBps != 0) {
                min = rebalancerCloseExpoImbalanceLimitBps + 1;
            }

            longImbalanceTargetBps = int256(bound(seed, uint256(min), uint256(closeExpoImbalanceLimitBps)));
        }

        return (
            openExpoImbalanceLimitBps,
            depositExpoImbalanceLimitBps,
            withdrawalExpoImbalanceLimitBps,
            closeExpoImbalanceLimitBps,
            rebalancerCloseExpoImbalanceLimitBps,
            longImbalanceTargetBps
        );
    }

    function setMinLongPositionPreconditions(uint256 seed) internal pure returns (uint256 minLongPosition) {
        uint256 minBound = 2 * 10 ** 18; // 2 tokens
        minLongPosition = bound(seed, minBound, MAX_MIN_LONG_POSITION);
    }

    function setSafetyMarginBpsPreconditions(uint256 seed) internal pure returns (uint256 safetyMarginBps) {
        uint256 minBound = 200; //2%
        safetyMarginBps = bound(seed, minBound, Constants.MAX_SAFETY_MARGIN_BPS);
    }

    function setLiquidationIterationPreconditions(uint256 seed) internal pure returns (uint16 liquidationIteration) {
        liquidationIteration = uint16(bound(seed, 1, Constants.MAX_LIQUIDATION_ITERATION));
    }

    function setTargetUsdnPricePreconditions(uint256 seed) internal view returns (uint128 price) {
        (uint128 minPrice, uint128 maxPrice) = usdnProtocol.getTargetUsdnPriceBounds();
        price = uint128(bound(seed, minPrice, maxPrice));
    }

    function setUsdnRebaseThresholdPreconditions(uint256 seed) internal view returns (uint128 threshold) {
        (uint128 minThreshold, uint128 maxThreshold) = usdnProtocol.getUsdnRebaseThresholdBounds();
        threshold = uint128(bound(seed, minThreshold, maxThreshold));
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Rebalancer                                 */
    /* -------------------------------------------------------------------------- */

    function setPositionMaxLeveragePreconditions(uint256 seed) internal view returns (uint256 maxLeverage) {
        uint256 protocolMaxLeverage = rebalancer.getPositionMaxLeverageBound();

        uint256 minLeverage = Constants.REBALANCER_MIN_LEVERAGE;

        if (minLeverage >= protocolMaxLeverage) {
            return minLeverage + 1;
        }

        maxLeverage = bound(seed, minLeverage + 1, protocolMaxLeverage);
    }

    function setMinAssetDepositPreconditions(uint256 seed) internal view returns (uint256 minAssetDeposit) {
        uint256 minLongPosition = rebalancer.getMinLongAssetDeposit();
        uint256 maxBound = 100 ether;

        minAssetDeposit = bound(seed, minLongPosition, maxBound);
    }

    function setTimeLimitsPreconditions(uint256 seed)
        internal
        view
        returns (uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay)
    {
        uint64 seed1 = uint64(seed);
        uint64 seed2 = uint64(seed >> 64);
        uint64 seed3 = uint64(seed >> 128);
        uint64 seed4 = uint64(seed >> 192);

        uint256 maxActionCooldown = rebalancer.MAX_ACTION_COOLDOWN();
        uint256 maxCloseDelay = rebalancer.MAX_CLOSE_DELAY();

        validationDelay = uint64(bound(seed1, 1 minutes, 1 hours));
        validationDeadline = uint64(bound(seed2, validationDelay + 1 minutes, validationDelay + 24 hours));
        actionCooldown = uint64(bound(seed3, validationDeadline, maxActionCooldown));
        closeDelay = uint64(bound(seed4, 0, maxCloseDelay));

        return (validationDelay, validationDeadline, actionCooldown, closeDelay);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidation Manger                             */
    /* -------------------------------------------------------------------------- */

    function setRewardsParametersPreconditions(uint256 seed)
        internal
        view
        returns (
            uint32 gasUsedPerTick,
            uint32 otherGasUsed,
            uint32 rebaseGasUsed,
            uint32 rebalancerGasUsed,
            uint64 baseFeeOffset,
            uint16 gasMultiplierBps,
            uint16 positionBonusMultiplierBps,
            uint128 fixedReward,
            uint128 maxReward
        )
    {
        (gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed) = _getGasParameters(seed);

        (baseFeeOffset, gasMultiplierBps, positionBonusMultiplierBps, fixedReward, maxReward) =
            _getRewardParameters(seed >> 128, fixedReward);
    }

    function _getGasParameters(uint256 seed)
        internal
        view
        returns (uint32 gasUsedPerTick, uint32 otherGasUsed, uint32 rebaseGasUsed, uint32 rebalancerGasUsed)
    {
        uint32 seed1 = uint32(seed);
        uint32 seed2 = uint32(seed >> 32);
        uint32 seed3 = uint32(seed >> 64);
        uint32 seed4 = uint32(seed >> 96);

        gasUsedPerTick = uint32(bound(seed1, 0, liquidationRewardsManager.MAX_GAS_USED_PER_TICK()));
        otherGasUsed = uint32(bound(seed2, 0, liquidationRewardsManager.MAX_OTHER_GAS_USED()));
        rebaseGasUsed = uint32(bound(seed3, 0, liquidationRewardsManager.MAX_REBASE_GAS_USED()));
        rebalancerGasUsed = uint32(bound(seed4, 0, liquidationRewardsManager.MAX_REBALANCER_GAS_USED()));
    }

    function _getRewardParameters(uint256 seed, uint128 _fixedReward)
        internal
        pure
        returns (
            uint64 baseFeeOffset,
            uint16 gasMultiplierBps,
            uint16 positionBonusMultiplierBps,
            uint128 fixedReward,
            uint128 maxReward
        )
    {
        uint64 seed5 = uint64(seed);
        uint16 seed6 = uint16(seed >> 64);
        uint16 seed7 = uint16(seed >> 80);
        uint128 seed8 = uint128(seed >> 96);

        baseFeeOffset = uint64(bound(seed5, 0, 1000 gwei));
        gasMultiplierBps = uint16(bound(seed6, 0, 10_000));
        positionBonusMultiplierBps = uint16(bound(seed7, 0, 10_000));

        fixedReward = uint128(bound(seed8 % 1000, 0, 10 ether));
        maxReward = uint128(bound((seed8 / 1000) % 1000, _fixedReward, 100 ether));
    }
}
