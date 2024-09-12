// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN } from "../../utils/Constants.sol";
import { Setup } from "../Setup.sol";
import { Utils } from "../helpers/Utils.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

contract FuzzActionsAdmin is Setup, Utils {
    /* -------------------------------------------------------------------------- */
    /*                               ADMIN functions                              */
    /* -------------------------------------------------------------------------- */

    function setMinLeverage(uint256 minLeverage) public {
        minLeverage = bound(minLeverage, 10 ** Constants.LEVERAGE_DECIMALS + 1, usdnProtocol.getMaxLeverage() - 1);
        vm.prank(ADMIN);
        usdnProtocol.setMinLeverage(minLeverage);
    }

    function setMaxLeverage(uint256 newMaxLeverage) public {
        newMaxLeverage =
            bound(newMaxLeverage, usdnProtocol.getMinLeverage() + 1, 100 * 10 ** Constants.LEVERAGE_DECIMALS);
        vm.prank(ADMIN);
        usdnProtocol.setMaxLeverage(newMaxLeverage);
    }

    function setValidationDeadline(uint256 newValidationDeadline) public {
        newValidationDeadline =
            bound(newValidationDeadline, Constants.MIN_VALIDATION_DEADLINE, Constants.MAX_VALIDATION_DEADLINE);
        vm.prank(ADMIN);
        usdnProtocol.setValidationDeadline(newValidationDeadline);
    }

    function setLiquidationPenalty(uint8 newLiquidationPenalty) public {
        newLiquidationPenalty = uint8(bound(newLiquidationPenalty, 0, Constants.MAX_LIQUIDATION_PENALTY));
        vm.prank(ADMIN);
        usdnProtocol.setLiquidationPenalty(newLiquidationPenalty);
    }

    function setSafetyMarginBps(uint256 newSafetyMarginBps) public {
        newSafetyMarginBps = bound(newSafetyMarginBps, 0, Constants.MAX_SAFETY_MARGIN_BPS);
        vm.prank(ADMIN);
        usdnProtocol.setSafetyMarginBps(newSafetyMarginBps);
    }

    function setLiquidationIteration(uint16 newLiquidationIteration) public {
        newLiquidationIteration = uint16(bound(newLiquidationIteration, 0, Constants.MAX_LIQUIDATION_ITERATION));
        vm.prank(ADMIN);
        usdnProtocol.setLiquidationIteration(newLiquidationIteration);
    }

    function setEMAPeriod(uint128 newEMAPeriod) public {
        newEMAPeriod = uint128(bound(newEMAPeriod, 0, Constants.MAX_EMA_PERIOD));
        vm.prank(ADMIN);
        usdnProtocol.setEMAPeriod(newEMAPeriod);
    }

    function setFundingSF(uint256 newFundingSF) public {
        newFundingSF = bound(newFundingSF, 0, 10 ** Constants.FUNDING_SF_DECIMALS);
        vm.prank(ADMIN);
        usdnProtocol.setFundingSF(newFundingSF);
    }

    function setProtocolFeeBps(uint16 newProtocolFeeBps) public {
        newProtocolFeeBps = uint16(bound(newProtocolFeeBps, 0, Constants.BPS_DIVISOR));
        vm.prank(ADMIN);
        usdnProtocol.setProtocolFeeBps(newProtocolFeeBps);
    }

    function setPositionFeeBps(uint16 newPositionFee) public {
        newPositionFee = uint16(bound(newPositionFee, 0, Constants.MAX_POSITION_FEE_BPS));
        vm.prank(ADMIN);
        usdnProtocol.setPositionFeeBps(newPositionFee);
    }

    function setVaultFeeBps(uint16 newVaultFee) public {
        newVaultFee = uint16(bound(newVaultFee, 0, Constants.MAX_VAULT_FEE_BPS));
        vm.prank(ADMIN);
        usdnProtocol.setVaultFeeBps(newVaultFee);
    }

    function setRebalancerBonusBps(uint16 newBonus) public {
        newBonus = uint16(bound(newBonus, 0, Constants.BPS_DIVISOR));
        vm.prank(ADMIN);
        usdnProtocol.setRebalancerBonusBps(newBonus);
    }

    function setSdexBurnOnDepositRatio(uint32 newRatio) public {
        newRatio = uint32(bound(newRatio, 0, Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR / 20));
        vm.prank(ADMIN);
        usdnProtocol.setSdexBurnOnDepositRatio(newRatio);
    }

    function setSecurityDepositValue(uint64 securityDepositValue) public {
        vm.prank(ADMIN);
        usdnProtocol.setSecurityDepositValue(securityDepositValue);
    }

    function setFeeThreshold(uint256 newFeeThreshold) public {
        vm.prank(ADMIN);
        usdnProtocol.setFeeThreshold(newFeeThreshold);
    }

    function setFeeCollector(address newFeeCollector) public {
        vm.prank(ADMIN);
        try usdnProtocol.setFeeCollector(newFeeCollector) { }
        catch (bytes memory err) {
            _checkErrors(err, SET_FEE_COLLECTOR_ERRORS);
        }
    }

    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) public {
        newOpenLimitBps = bound(newOpenLimitBps, 1, uint256(type(int256).max));
        newWithdrawalLimitBps = bound(newWithdrawalLimitBps, newOpenLimitBps, uint256(type(int256).max));
        newDepositLimitBps = bound(newDepositLimitBps, 1, uint256(type(int256).max));
        newCloseLimitBps = bound(newCloseLimitBps, newDepositLimitBps, uint256(type(int256).max));
        if (newWithdrawalLimitBps > Constants.BPS_DIVISOR / 2) {
            newLongImbalanceTargetBps =
                bound(newLongImbalanceTargetBps, -int256(Constants.BPS_DIVISOR / 2), int256(newCloseLimitBps));
        } else {
            newLongImbalanceTargetBps =
                bound(newLongImbalanceTargetBps, -int256(newWithdrawalLimitBps), int256(newCloseLimitBps));
        }
        vm.prank(ADMIN);
        usdnProtocol.setExpoImbalanceLimits(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        );
    }

    function setTargetUsdnPrice(uint128 newPrice) public {
        newPrice =
            uint128(bound(newPrice, 10 ** usdnProtocol.getPriceFeedDecimals(), usdnProtocol.getUsdnRebaseThreshold()));
        vm.prank(ADMIN);
        usdnProtocol.setTargetUsdnPrice(newPrice);
    }

    function setUsdnRebaseThreshold(uint128 newThreshold) public {
        newThreshold = uint128(bound(newThreshold, usdnProtocol.getTargetUsdnPrice(), type(uint128).max));
        vm.prank(ADMIN);
        usdnProtocol.setUsdnRebaseThreshold(newThreshold);
    }

    function setUsdnRebaseInterval(uint256 newInterval) public {
        vm.prank(ADMIN);
        usdnProtocol.setUsdnRebaseInterval(newInterval);
    }

    function setMinLongPosition(uint256 newMinLongPosition) public {
        vm.prank(ADMIN);
        usdnProtocol.setMinLongPosition(newMinLongPosition);
    }
}
