// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";
import { Setup } from "../Setup.sol";

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract FuzzActions is Setup {
    using SafeCast for uint256;
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initiateDeposit(
        uint128 amountWstETHRand,
        uint128 amountSdexRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 currentPrice
    ) public {
        wsteth.mintAndApprove(msg.sender, amountWstETHRand, address(usdnProtocol), amountWstETHRand);
        sdex.mintAndApprove(msg.sender, amountSdexRand, address(usdnProtocol), amountSdexRand);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        bytes memory priceData = abi.encode(currentPrice);

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountWstETHRand);
            assert(sdex.balanceOf(msg.sender) < balancesBefore.senderSdex);
            assert(address(usdnProtocol).balance == balancesBefore.protocolEth + securityDeposit);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth + amountWstETHRand);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_DEPOSIT_ERRORS);
        }
    }

    function initiateOpenPosition(
        uint128 amountRand,
        uint128 liquidationPriceRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 currentPrice
    ) public {
        wsteth.mintAndApprove(msg.sender, amountRand, address(usdnProtocol), amountRand);
        uint256 destRandBounded = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        vm.deal(msg.sender, ethRand);

        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address dest = destinationsToken[address(wsteth)][destRandBounded];
        address validator = validators[validatorRand];
        bytes memory priceData = abi.encode(currentPrice);
        uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);

        vm.prank(msg.sender);
        try usdnProtocol.initiateOpenPosition{ value: ethRand }(
            amountRand, liquidationPriceRand, dest, payable(validator), NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        ) returns (bool, IUsdnProtocolTypes.PositionId memory posId) {
            posIds.push(posId);

            assert(address(usdnProtocol).balance == balancesBefore.protocolEth + securityDeposit);
            assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);

            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth + amountRand);
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountRand);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }

    function initiateWithdrawal(
        uint152 usdnShares,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 currentPrice
    ) public {
        vm.prank(msg.sender);
        usdn.approve(address(usdnProtocol), usdnShares);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        bytes memory priceData = abi.encode(currentPrice);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);

        vm.prank(msg.sender);
        try usdnProtocol.initiateWithdrawal{ value: ethRand }(
            usdnShares, dest, validator, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);
            assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares - usdnShares);

            assert(address(usdnProtocol).balance == balancesBefore.protocolEth + securityDeposit);
            assert(usdn.sharesOf(address(usdnProtocol)) == balancesBefore.protocolUsdnShares + usdnShares);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateDeposit(uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        bytes memory priceData = abi.encode(currentPrice);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        IUsdnProtocolTypes.DepositPendingAction memory pendingAction =
            usdnProtocol.i_toDepositPendingAction(usdnProtocol.getUserPendingAction(validator));

        vm.prank(msg.sender);
        try usdnProtocol.validateDeposit(validator, priceData, EMPTY_PREVIOUS_DATA) returns (bool success_) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            if (success_) {
                //todo maybe determine the exact amount if it can be know before the call
                assert(usdn.sharesOf(pendingAction.to) > balancesBefore.toUsdnShares);
                if (pendingAction.to != msg.sender) {
                    assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares);
                }
                if (pendingAction.to != validator) {
                    assert(usdn.sharesOf(validator) == balancesBefore.validatorUsdnShares);
                }
            } else {
                assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares);
                assert(usdn.sharesOf(validator) == balancesBefore.validatorUsdnShares);
                assert(usdn.sharesOf(pendingAction.to) == balancesBefore.toUsdnShares);
            }

            assert(validator.balance == balancesBefore.validatorEth + securityDeposit);

            assert(usdn.sharesOf(address(usdnProtocol)) == balancesBefore.protocolUsdnShares);

            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth);
            assert(wsteth.balanceOf(validator) == balancesBefore.validatorWsteth);
            assert(wsteth.balanceOf(pendingAction.to) == balancesBefore.toWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_DEPOSIT_ERRORS);
        }
    }

    function validateWithdrawal(uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        bytes memory priceData = abi.encode(currentPrice);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(validator);

        vm.prank(msg.sender);
        try usdnProtocol.validateWithdrawal(validator, priceData, EMPTY_PREVIOUS_DATA) returns (bool success_) {
            assert(address(msg.sender).balance == balancesBefore.senderEth + action.securityDepositValue);
            if (success_) {
                assert(wsteth.balanceOf(msg.sender) >= balancesBefore.senderWsteth);

                assert(address(usdnProtocol).balance == balancesBefore.protocolEth - action.securityDepositValue);
                assert(usdn.sharesOf(address(usdnProtocol)) < balancesBefore.protocolUsdnShares);
                assert(wsteth.balanceOf(address(usdnProtocol)) <= balancesBefore.protocolWsteth);
            } else {
                assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
                assert(usdn.sharesOf(address(usdnProtocol)) == balancesBefore.protocolUsdnShares);
                assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth);
            }
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateOpen(uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        bytes memory priceData = abi.encode(currentPrice);
        uint64 securityDeposit = usdnProtocol.getUserPendingAction(validator).securityDepositValue;

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);

        vm.prank(msg.sender);
        try usdnProtocol.validateOpenPosition(validator, priceData, EMPTY_PREVIOUS_DATA) returns (bool success) {
            if (success) {
                assert(address(validator).balance == balancesBefore.validatorEth + securityDeposit);
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth - securityDeposit);
            } else {
                assert(address(validator).balance == balancesBefore.validatorEth);
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
            }
            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth);
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
        }
    }

    function validatePendingActions(uint256 maxValidations, uint256 currentPrice) public {
        uint256 balanceBefore = address(msg.sender).balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 securityDeposit;

        (IUsdnProtocolTypes.PendingAction[] memory actions, uint128[] memory rawIndices) =
            usdnProtocol.getActionablePendingActions(address(0));
        if (rawIndices.length == 0) {
            return;
        }
        bytes[] memory priceData = new bytes[](rawIndices.length);
        for (uint256 i = 0; i < rawIndices.length; i++) {
            priceData[i] = abi.encode(currentPrice);
            securityDeposit += actions[i].securityDepositValue;
        }
        IUsdnProtocolTypes.PreviousActionsData memory previousActionsData =
            IUsdnProtocolTypes.PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });

        vm.prank(msg.sender);
        try usdnProtocol.validateActionablePendingActions(previousActionsData, maxValidations) returns (
            uint256 validatedActions
        ) {
            assert(
                actions.length < maxValidations
                    ? validatedActions == actions.length
                    : validatedActions == maxValidations
            );
            assert(address(msg.sender).balance == balanceBefore + securityDeposit);
            assert(address(usdnProtocol).balance == balanceBeforeProtocol - securityDeposit);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_PENDING_ACTIONS_ERRORS);
        }
    }

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
        if (newFeeCollector != address(0)) {
            usdnProtocol.setFeeCollector(newFeeCollector);
        }
    }

    function setExpoImbalanceLimits(
        uint256 newOpenLimitBps,
        uint256 newDepositLimitBps,
        uint256 newWithdrawalLimitBps,
        uint256 newCloseLimitBps,
        int256 newLongImbalanceTargetBps
    ) public {
        try usdnProtocol.setExpoImbalanceLimits(
            newOpenLimitBps, newDepositLimitBps, newWithdrawalLimitBps, newCloseLimitBps, newLongImbalanceTargetBps
        ) {
            assert(usdnProtocol.getOpenExpoImbalanceLimitBps() == newOpenLimitBps.toInt256());
            assert(usdnProtocol.getDepositExpoImbalanceLimitBps() == newDepositLimitBps.toInt256());
            assert(usdnProtocol.getWithdrawalExpoImbalanceLimitBps() == newWithdrawalLimitBps.toInt256());
            assert(usdnProtocol.getCloseExpoImbalanceLimitBps() == newCloseLimitBps.toInt256());
            assert(usdnProtocol.getLongImbalanceTargetBps() == newLongImbalanceTargetBps);
        } catch (bytes memory err) {
            _checkErrors(err, ADMIN_ERRORS);
        }
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
