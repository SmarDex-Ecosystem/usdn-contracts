// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { Setup } from "../Setup.sol";

contract FuzzActionsAdmin is Setup {
    /* -------------------------------------------------------------------------- */
    /*                               ADMIN functions                              */
    /* -------------------------------------------------------------------------- */

    function setMinLeverage(uint256 minLeverage) public {
        minLeverage = bound(minLeverage, 10 ** Constants.LEVERAGE_DECIMALS + 1, usdnProtocol.getMaxLeverage() - 1);
        usdnProtocol.setMinLeverage(minLeverage);
    }

    function setMaxLeverage(uint256 newMaxLeverage) public {
        newMaxLeverage =
            bound(newMaxLeverage, usdnProtocol.getMinLeverage() + 1, 100 * 10 ** Constants.LEVERAGE_DECIMALS);
        usdnProtocol.setMaxLeverage(newMaxLeverage);
    }

    function setValidationDeadline(uint256 newValidationDeadline) public {
        newValidationDeadline = bound(newValidationDeadline, 60, 1 days);
        usdnProtocol.setValidationDeadline(newValidationDeadline);
    }

    function setLiquidationPenalty(uint8 newLiquidationPenalty) public {
        newLiquidationPenalty = uint8(bound(newLiquidationPenalty, 0, 15));
        usdnProtocol.setLiquidationPenalty(newLiquidationPenalty);
    }

    function setSafetyMarginBps(uint256 newSafetyMarginBps) public {
        newSafetyMarginBps = bound(newSafetyMarginBps, 0, 2000);
        usdnProtocol.setSafetyMarginBps(newSafetyMarginBps);
    }

    function setLiquidationIteration(uint16 newLiquidationIteration) public {
        newLiquidationIteration = uint16(bound(newLiquidationIteration, 0, Constants.MAX_LIQUIDATION_ITERATION));
        usdnProtocol.setLiquidationIteration(newLiquidationIteration);
    }

    function setEMAPeriod(uint128 newEMAPeriod) public {
        newEMAPeriod = uint128(bound(newEMAPeriod, 0, 90 days));
        usdnProtocol.setEMAPeriod(newEMAPeriod);
    }

    function setFundingSF(uint256 newFundingSF) public {
        newFundingSF = bound(newFundingSF, 0, 10 ** Constants.FUNDING_SF_DECIMALS);
        usdnProtocol.setFundingSF(newFundingSF);
    }

    function setProtocolFeeBps(uint16 newProtocolFeeBps) public {
        newProtocolFeeBps = uint16(bound(newProtocolFeeBps, 0, Constants.BPS_DIVISOR));
        usdnProtocol.setProtocolFeeBps(newProtocolFeeBps);
    }

    function setPositionFeeBps(uint16 newPositionFee) public {
        newPositionFee = uint16(bound(newPositionFee, 0, 2000));
        usdnProtocol.setPositionFeeBps(newPositionFee);
    }

    function setVaultFeeBps(uint16 newVaultFee) public {
        newVaultFee = uint16(bound(newVaultFee, 0, 2000));
        usdnProtocol.setVaultFeeBps(newVaultFee);
    }

    function setRebalancerBonusBps(uint16 newBonus) public {
        newBonus = uint16(bound(newBonus, 0, Constants.BPS_DIVISOR));
        usdnProtocol.setRebalancerBonusBps(newBonus);
    }

    function setSdexBurnOnDepositRatio(uint32 newRatio) public {
        newRatio = uint32(bound(newRatio, 0, Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20));
        usdnProtocol.setSdexBurnOnDepositRatio(newRatio);
    }

    function setSecurityDepositValue(uint64 securityDepositValue) public {
        usdnProtocol.setSecurityDepositValue(securityDepositValue);
    }

    function setFeeThreshold(uint256 newFeeThreshold) public {
        usdnProtocol.setFeeThreshold(newFeeThreshold);
    }

    function setFeeCollector(address newFeeCollector) public {
        require(newFeeCollector != address(0));
        usdnProtocol.setFeeCollector(newFeeCollector);
    }

    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) public {
        require(newWithdrawalLimitBps == 0 || newWithdrawalLimitBps >= newOpenLimitBps);
        require((newCloseLimitBps == 0 || newCloseLimitBps >= newDepositLimitBps));
        require(
            newLongImbalanceTargetBps <= int256(newCloseLimitBps)
                && newLongImbalanceTargetBps >= -int256(newWithdrawalLimitBps)
                && newLongImbalanceTargetBps >= -int256(Constants.BPS_DIVISOR / 2)
        );
        usdnProtocol.setExpoImbalanceLimits(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    function setTargetUsdnPrice(uint128 newPrice) public {
        newPrice =
            uint128(bound(newPrice, 10 ** usdnProtocol.getPriceFeedDecimals(), usdnProtocol.getUsdnRebaseThreshold()));
        usdnProtocol.setTargetUsdnPrice(newPrice);
    }

    function setUsdnRebaseThreshold(uint128 newThreshold) public {
        newThreshold = uint128(bound(newThreshold, usdnProtocol.getTargetUsdnPrice(), type(uint128).max));
        usdnProtocol.setUsdnRebaseThreshold(newThreshold);
    }

    function setUsdnRebaseInterval(uint256 newInterval) public {
        usdnProtocol.setUsdnRebaseInterval(newInterval);
    }

    function setMinLongPosition(uint256 newMinLongPosition) public {
        usdnProtocol.setMinLongPosition(newMinLongPosition);
    }
}
