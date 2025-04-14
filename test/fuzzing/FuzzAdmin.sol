// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PostconditionsAdmin } from "./helper/postconditions/PostconditionsAdmin.sol";
import { PreconditionsAdmin } from "./helper/preconditions/PreconditionsAdmin.sol";

contract FuzzAdmin is PreconditionsAdmin, PostconditionsAdmin {
    /* -------------------------------------------------------------------------- */
    /*                                USDN Protocol                               */
    /* -------------------------------------------------------------------------- */

    function fuzz_setValidatorDeadlines(uint256 seed) public {
        (uint128 newLowLatencyDeadline, uint128 newOnChainDeadline) = setValidationsDeadlinesPreconditions(seed);

        (bool success, bytes memory returnData) = _setValidationDeadlines(newLowLatencyDeadline, newOnChainDeadline);
        setValidatorDeadlinesPostconditions(success, returnData);
    }

    function fuzz_setMinLeverage(uint256 seed) public {
        uint256 newMinLeverage = setMinLeveragePreconditions(seed);

        (bool success, bytes memory returnData) = _setMinLeverage(newMinLeverage);
        setMinLeveragePostconditions(success, returnData);
    }

    function fuzz_setMaxLeverage(uint256 seed) public {
        uint256 newMaxLeverage = setMaxLeveragePreconditions(seed);

        (bool success, bytes memory returnData) = _setMaxLeverage(newMaxLeverage);
        setMaxLeveragePostconditions(success, returnData);
    }

    function fuzz_setLiquidationPenalty(uint256 seed) public {
        uint24 newLiquidationPenalty = setLiquidationPenaltyPreconditions(seed);

        (bool success, bytes memory returnData) = _setLiquidationPenalty(newLiquidationPenalty);
        setLiquidationPenaltyPostconditions(success, returnData);
    }

    function fuzz_setEMAPeriod(uint256 seed) public {
        uint128 newEmaPeriod = setEMAPeriodPreconditions(seed);

        (bool success, bytes memory returnData) = _setEMAPeriod(newEmaPeriod);
        setEMAPeriodPostconditions(success, returnData);
    }

    function fuzz_setFundingSF(uint256 seed) public {
        uint256 newFundingSF = setFundingSFPreconditions(seed);

        (bool success, bytes memory returnData) = _setFundingSF(newFundingSF);
        setFundingSFPostconditions(success, returnData);
    }

    function fuzz_setProtocolFeeBps(uint256 seed) public {
        uint16 newProtocolFeeBps = setProtocolFeeBpsPreconditions(seed);

        (bool success, bytes memory returnData) = _setProtocolFeeBps(newProtocolFeeBps);
        setProtocolFeeBpsPostconditions(success, returnData);
    }

    function fuzz_setPositionFeeBps(uint256 seed) public {
        uint16 newPositionFee = setPositionFeeBpsPreconditions(seed);

        (bool success, bytes memory returnData) = _setPositionFeeBps(newPositionFee);
        setPositionFeeBpsPostconditions(success, returnData);
    }

    function fuzz_setVaultFeeBps(uint256 seed) public {
        uint16 newVaultFee = setVaultFeeBpsPreconditions(seed);

        (bool success, bytes memory returnData) = _setVaultFeeBps(newVaultFee);
        setVaultFeeBpsPostconditions(success, returnData);
    }

    function fuzz_setSdexRewardsRatioBps(uint256 seed) public {
        uint16 newRewards = setSdexRewardsRatioBpsPreconditions(seed);

        (bool success, bytes memory returnData) = _setSdexRewardsRatioBps(newRewards);
        setSdexRewardsRatioBpsPostconditions(success, returnData);
    }

    function fuzz_setRebalancerBonusBps(uint256 seed) public {
        uint16 newBonus = setRebalancerBonusBpsPreconditions(seed);

        (bool success, bytes memory returnData) = _setRebalancerBonusBps(newBonus);
        setRebalancerBonusBpsPostconditions(success, returnData);
    }

    function fuzz_setSdexBurnOnDepositRatio(uint256 seed) public {
        uint32 newRatio = setSdexBurnOnDepositRatioPreconditions(seed);

        (bool success, bytes memory returnData) = _setSdexBurnOnDepositRatio(newRatio);
        setSdexBurnOnDepositRatioPostconditions(success, returnData);
    }

    function fuzz_setSecurityDepositValue(uint256 seed) public {
        uint64 newSecurityDeposit = setSecurityDepositValuePreconditions(seed);

        (bool success, bytes memory returnData) = _setSecurityDepositValue(newSecurityDeposit);
        setSecurityDepositValuePostconditions(success, returnData);
    }

    function fuzz_setExpoImbalanceLimits(uint256 seed) public {
        (
            uint256 newOpenLimitBps,
            uint256 newDepositLimitBps,
            uint256 newWithdrawalLimitBps,
            uint256 newCloseLimitBps,
            uint256 newRebalancerCloseLimitBps,
            int256 newLongImbalanceTargetBps
        ) = setExpoImbalanceLimitsPreconditions(seed);

        (bool success, bytes memory returnData) = _setExpoImbalanceLimits(
            newOpenLimitBps,
            newDepositLimitBps,
            newWithdrawalLimitBps,
            newCloseLimitBps,
            newRebalancerCloseLimitBps,
            newLongImbalanceTargetBps
        );

        setExpoImbalanceLimitsPostconditions(success, returnData);
    }

    function fuzz_setMinLongPosition(uint256 seed) public {
        uint256 newMinLongPosition = setMinLongPositionPreconditions(seed);

        (bool success, bytes memory returnData) = _setMinLongPosition(newMinLongPosition);
        setMinLongPositionPostconditions(success, returnData);
    }

    function fuzz_setSafetyMarginBps(uint256 seed) public {
        uint256 newSafetyMarginBps = setSafetyMarginBpsPreconditions(seed);

        (bool success, bytes memory returnData) = _setSafetyMarginBps(newSafetyMarginBps);
        setSafetyMarginBpsPostconditions(success, returnData);
    }

    function fuzz_setLiquidationIteration(uint256 seed) public {
        uint16 newLiquidationIteration = setLiquidationIterationPreconditions(seed);

        (bool success, bytes memory returnData) = _setLiquidationIteration(newLiquidationIteration);
        setLiquidationIterationPostconditions(success, returnData);
    }

    function fuzz_setFeeThreshold(uint256 seed) public {
        // since there are no restrictions on feeThreshold besides uint256
        (bool success, bytes memory returnData) = _setFeeThreshold(seed + 1 ether);
        setFeeThresholdPostconditions(success, returnData);
    }

    function fuzz_setTargetUsdnPrice(uint256 seed) public {
        uint128 newPrice = setTargetUsdnPricePreconditions(seed);

        (bool success, bytes memory returnData) = _setTargetUsdnPrice(newPrice);
        setTargetUsdnPricePostconditions(success, returnData);
    }

    function fuzz_setUsdnRebaseThreshold(uint256 seed) public {
        uint128 newThreshold = setUsdnRebaseThresholdPreconditions(seed);

        (bool success, bytes memory returnData) = _setUsdnRebaseThreshold(newThreshold);
        setUsdnRebaseThresholdPostconditions(success, returnData);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Rebalancer                                 */
    /* -------------------------------------------------------------------------- */

    function fuzz_setPositionMaxLeverage(uint256 seed) public {
        uint256 newMaxLeverage = setPositionMaxLeveragePreconditions(seed);

        (bool success, bytes memory returnData) = _setPositionMaxLeverage(newMaxLeverage);
        setPositionMaxLeveragePostconditions(success, returnData);
    }

    function fuzz_setMinAssetDeposit(uint256 seed) public {
        uint256 newMinAssetDeposit = setMinAssetDepositPreconditions(seed);

        (bool success, bytes memory returnData) = _setMinAssetDeposit(newMinAssetDeposit);
        setMinAssetDepositPostconditions(success, returnData);
    }

    function fuzz_setTimeLimits(uint256 seed) public {
        (uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay) =
            setTimeLimitsPreconditions(seed);

        (bool success, bytes memory returnData) =
            _setTimeLimits(validationDelay, validationDeadline, actionCooldown, closeDelay);

        setTimeLimitsPostconditions(success, returnData);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidation Manger                             */
    /* -------------------------------------------------------------------------- */

    function fuzz_setRewardsParameters(uint256 seed) public {
        (
            uint32 gasUsedPerTick,
            uint32 otherGasUsed,
            uint32 rebaseGasUsed,
            uint32 rebalancerGasUsed,
            uint64 baseFeeOffset,
            uint16 gasMultiplierBps,
            uint16 positionBonusMultiplierBps,
            uint128 fixedReward,
            uint128 maxReward
        ) = setRewardsParametersPreconditions(seed);

        (bool success, bytes memory returnData) = _setRewardsParameters(
            gasUsedPerTick,
            otherGasUsed,
            rebaseGasUsed,
            rebalancerGasUsed,
            baseFeeOffset,
            gasMultiplierBps,
            positionBonusMultiplierBps,
            fixedReward,
            maxReward
        );

        setRewardsParametersPostconditions(success, returnData);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Internal Helpers                              */
    /* -------------------------------------------------------------------------- */

    function fuzz_setPrice(int256 priceChangePercent) public {
        SetPricePreconditions memory params = setPricePreconditions(priceChangePercent);

        int256 newPriceUSD = params.newPrice;

        setChainlinkPrice(newPriceUSD);
        setPythPrice(newPriceUSD);
    }

    function setChainlinkPrice(int256 priceUSD) internal {
        int256 scaledPrice = priceUSD * int256(10 ** chainlink.decimals());
        chainlink.setLastPrice(scaledPrice);
        chainlink.setLastPublishTime(block.timestamp);

        uint80 roundId = 1;
        uint256 startedAt = block.timestamp;
        uint80 answeredInRound = 1;

        chainlink.setLatestRoundData(roundId, scaledPrice, startedAt, answeredInRound);
    }

    function setPythPrice(int256 priceUSD) internal {
        pyth.setLastPublishTime(block.timestamp + wstEthOracleMiddleware.getValidationDelay());
        pyth.setPrice(int64(priceUSD * int64(uint64(10 ** chainlink.decimals()))));
        pyth.setConf(0); //NOTE: confidence hardcoded to 0
    }

    function pumpPrice(uint256 loops) internal {
        loops = loops > 20 ? 20 : loops;
        for (uint256 i; i < loops; ++i) {
            fuzz_setPrice((type(int256).max / 5));
        }
    }

    //will not dump below 1500 in a default anti liquidation mode
    function crashPrice(uint256 loops) internal {
        loops = loops > 20 ? 20 : loops;
        for (uint256 i; i < loops; ++i) {
            fuzz_setPrice(-10_000);
        }
    }
}
