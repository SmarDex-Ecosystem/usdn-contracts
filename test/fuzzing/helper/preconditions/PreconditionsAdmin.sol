// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PreconditionsBase } from "./PreconditionsBase.sol";

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
        returns (uint128 lowLatencyDeadline, uint128 onChainDeadline)
    {
        (lowLatencyDeadline, onChainDeadline) = usdnProtocol.getValidatorDeadlines(seed);
    }

    function setMinLeveragePreconditions(uint256 seed) internal returns (uint256 minLeverage) {
        minLeverage = usdnProtocol.getMinLeverage(seed);
    }

    function setMaxLeveragePreconditions(uint256 seed) internal returns (uint256 minLeverage) {
        minLeverage = usdnProtocol.getMaxLeverage(seed);
    }

    function setLiquidationPenaltyPreconditions(uint256 seed) internal returns (uint24 liquidationPenalty) {
        liquidationPenalty = usdnProtocol.getLiquidationPenalty(seed);
    }

    function setEMAPeriodPreconditions(uint256 seed) internal returns (uint128 emaPeriod) {
        emaPeriod = usdnProtocol.getEMAPeriod(seed);
    }

    function setFundingSFPreconditions(uint256 seed) internal returns (uint256 fundingSF) {
        fundingSF = usdnProtocol.getFundingSF(seed);
    }

    function setProtocolFeeBpsPreconditions(uint256 seed) internal returns (uint16 protocolFeeBps) {
        protocolFeeBps = usdnProtocol.getProtocolFeeBps(seed);
    }

    function setPositionFeeBpsPreconditions(uint256 seed) internal returns (uint16 positionFee) {
        positionFee = usdnProtocol.getPositionFeeBps(seed);
    }

    function setVaultFeeBpsPreconditions(uint256 seed) internal returns (uint16 vaultFee) {
        vaultFee = usdnProtocol.getVaultFeeBps(seed);
    }

    function setSdexRewardsRatioBpsPreconditions(uint256 seed) internal returns (uint16 rewards) {
        rewards = usdnProtocol.getSdexRewardsRatioBps(seed);
    }

    function setRebalancerBonusBpsPreconditions(uint256 seed) internal returns (uint16 bonus) {
        bonus = usdnProtocol.getRebalancerBonusBps(seed);
    }

    function setSdexBurnOnDepositRatioPreconditions(uint256 seed) internal returns (uint32 ratio) {
        ratio = usdnProtocol.getSdexBurnOnDepositRatio(seed);
    }

    function setSecurityDepositValuePreconditions(uint256 seed) internal returns (uint64 securityDeposit) {
        securityDeposit = usdnProtocol.getSecurityDepositValue(seed);
    }

    function setExpoImbalanceLimitsPreconditions(
        uint256 seed1,
        uint256 seed2,
        uint256 seed3,
        uint256 seed4,
        uint256 seed5,
        int256 seed6
    )
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
        return usdnProtocol.getExpoImbalanceLimits(seed1, seed2, seed3, seed4, seed5, seed6);
    }

    function setMinLongPositionPreconditions(uint256 seed) internal returns (uint256 minLongPosition) {
        minLongPosition = usdnProtocol.getMinLongPosition(seed);
    }

    function setSafetyMarginBpsPreconditions(uint256 seed) internal returns (uint256 safetyMarginBps) {
        safetyMarginBps = usdnProtocol.getSafetyMarginBps(seed);
    }

    function setLiquidationIterationPreconditions(uint256 seed) internal returns (uint16 liquidationIteration) {
        liquidationIteration = usdnProtocol.getLiquidationIteration(seed);
    }

    function setTargetUsdnPricePreconditions(uint256 seed) internal returns (uint128 price) {
        price = usdnProtocol.getTargetUsdnPrice(seed);
    }

    function setUsdnRebaseThresholdPreconditions(uint256 seed) internal returns (uint128 threshold) {
        threshold = usdnProtocol.getUsdnRebaseThreshold(seed);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Rebalancer                                 */
    /* -------------------------------------------------------------------------- */

    function setPositionMaxLeveragePreconditions(uint256 seed) internal view returns (uint256 maxLeverage) {
        maxLeverage = rebalancer.getPositionMaxLeverage(seed);
    }

    function setMinAssetDepositPreconditions(uint256 seed) internal view returns (uint256 minAssetDeposit) {
        minAssetDeposit = rebalancer.getMinAssetDeposit(seed);
    }

    function setTimeLimitsPreconditions(uint256 seed)
        internal
        returns (uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay)
    {
        return rebalancer.getTimeLimits(seed);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidation Manger                             */
    /* -------------------------------------------------------------------------- */

    // function setRewardsParametersPreconditions(
    //     uint256 seed1,
    //     uint256 seed2,
    //     uint256 seed3,
    //     uint256 seed4,
    //     uint256 seed5,
    //     uint256 seed6,
    //     uint256 seed7,
    //     uint256 seed8,
    //     uint256 seed9
    // )
    //     internal
    //     returns (
    //         uint32 gasUsedPerTick,
    //         uint32 otherGasUsed,
    //         uint32 rebaseGasUsed,
    //         uint32 rebalancerGasUsed,
    //         uint64 baseFeeOffset,
    //         uint16 gasMultiplierBps,
    //         uint16 positionBonusMultiplierBps,
    //         uint128 fixedReward,
    //         uint128 maxReward
    //     )
    // {
    //     return liquidationRewardsManager.getRewardsParameters(
    //         seed1, seed2, seed3, seed4, seed5, seed6, seed7, seed8, seed9
    //     );
    // }
}
