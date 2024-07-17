// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";
import { Setup } from "../Setup.sol";

contract FuzzActions is Setup {
    struct InitiateDepositBalanceBefore {
        uint256 senderETH;
        uint256 senderWstETH;
        uint256 senderSdex;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolWstETH;
    }

    struct InitiateWithdrawalBalanceBefore {
        uint256 senderETH;
        uint256 senderUsdn;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolUsdn;
    }

    struct ValidateWithdrawalBalanceBefore {
        uint256 senderETH;
        uint256 senderWstETH;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolUsdn;
        uint256 usdnProtocolWstETH;
    }

    struct OpenPositionParams {
        address dest;
        address payable validator;
        bytes priceData;
        uint256 senderBalanceETH;
        uint256 senderBalanceWstETH;
        uint256 usdnProtocolBalanceETH;
        uint256 usdnProtocolBalanceWstETH;
        uint64 securityDeposit;
    }

    struct ValidateDepositBalanceBefore {
        uint256 senderWstETH;
        uint256 senderETH;
        uint256 senderUsdn;
        uint256 usdnProtocolWstETH;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolUsdn;
        uint256 validatorWstETH;
        uint256 validatorETH;
        uint256 validatorUsdn;
        uint256 toWstETH;
        uint256 toETH;
        uint256 toUsdn;
    }
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

        InitiateDepositBalanceBefore memory balanceBefore = InitiateDepositBalanceBefore({
            senderETH: address(msg.sender).balance,
            senderWstETH: wsteth.balanceOf(msg.sender),
            senderSdex: sdex.balanceOf(msg.sender),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolWstETH: wsteth.balanceOf(address(usdnProtocol))
        });

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balanceBefore.senderETH - securityDeposit);
            assert(wsteth.balanceOf(msg.sender) == balanceBefore.senderWstETH - amountWstETHRand);
            assert(sdex.balanceOf(msg.sender) < balanceBefore.senderSdex);
            assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH + securityDeposit);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balanceBefore.usdnProtocolWstETH + amountWstETHRand);
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
        OpenPositionParams memory params = OpenPositionParams({
            dest: destinationsToken[address(wsteth)][destRandBounded],
            validator: payable(validators[validatorRand]),
            priceData: abi.encode(currentPrice),
            senderBalanceETH: address(msg.sender).balance,
            senderBalanceWstETH: wsteth.balanceOf(msg.sender),
            usdnProtocolBalanceETH: address(usdnProtocol).balance,
            usdnProtocolBalanceWstETH: wsteth.balanceOf(address(usdnProtocol)),
            securityDeposit: usdnProtocol.getSecurityDepositValue()
        });

        vm.prank(msg.sender);
        try usdnProtocol.initiateOpenPosition{ value: ethRand }(
            amountRand,
            liquidationPriceRand,
            params.dest,
            params.validator,
            NO_PERMIT2,
            params.priceData,
            EMPTY_PREVIOUS_DATA
        ) returns (bool, IUsdnProtocolTypes.PositionId memory posId) {
            posIds.push(posId);

            assert(address(usdnProtocol).balance == params.usdnProtocolBalanceETH + params.securityDeposit);
            assert(address(msg.sender).balance == params.senderBalanceETH - params.securityDeposit);

            assert(wsteth.balanceOf(address(usdnProtocol)) == params.usdnProtocolBalanceWstETH + amountRand);
            assert(wsteth.balanceOf(msg.sender) == params.senderBalanceWstETH - amountRand);
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

        InitiateWithdrawalBalanceBefore memory balanceBefore = InitiateWithdrawalBalanceBefore({
            senderETH: address(msg.sender).balance,
            senderUsdn: usdn.sharesOf(msg.sender),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolUsdn: usdn.sharesOf(address(usdnProtocol))
        });

        vm.prank(msg.sender);
        try usdnProtocol.initiateWithdrawal{ value: ethRand }(
            usdnShares, dest, validator, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balanceBefore.senderETH - securityDeposit);
            assert(usdn.sharesOf(msg.sender) == balanceBefore.senderUsdn - usdnShares);

            assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH + securityDeposit);
            assert(usdn.sharesOf(address(usdnProtocol)) == balanceBefore.usdnProtocolUsdn + usdnShares);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateDeposit(uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(currentPrice);

        IUsdnProtocolTypes.DepositPendingAction memory pendingAction =
            usdnProtocol.i_toDepositPendingAction(usdnProtocol.getUserPendingAction(validator));

        ValidateDepositBalanceBefore memory balanceBefore = ValidateDepositBalanceBefore({
            senderWstETH: wsteth.balanceOf(msg.sender),
            senderETH: address(msg.sender).balance,
            senderUsdn: usdn.sharesOf(msg.sender),
            usdnProtocolWstETH: wsteth.balanceOf(address(usdnProtocol)),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolUsdn: usdn.sharesOf(address(usdnProtocol)),
            validatorWstETH: wsteth.balanceOf(validator),
            validatorETH: validator.balance,
            validatorUsdn: usdn.sharesOf(validator),
            toWstETH: wsteth.balanceOf(pendingAction.to),
            toETH: pendingAction.to.balance,
            toUsdn: usdn.sharesOf(pendingAction.to)
        });

        vm.prank(msg.sender);
        try usdnProtocol.validateDeposit(validator, priceData, EMPTY_PREVIOUS_DATA) returns (bool success_) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            if (success_) {
                //todo maybe determine the exact amount if it can be know before the call
                assert(usdn.sharesOf(pendingAction.to) > balanceBefore.toUsdn);
                if (pendingAction.to != msg.sender) {
                    assert(usdn.sharesOf(msg.sender) == balanceBefore.senderUsdn);
                }
                if (pendingAction.to != validator) {
                    assert(usdn.sharesOf(validator) == balanceBefore.validatorUsdn);
                }
            } else {
                assert(usdn.sharesOf(msg.sender) == balanceBefore.senderUsdn);
                assert(usdn.sharesOf(validator) == balanceBefore.validatorUsdn);
                assert(usdn.sharesOf(pendingAction.to) == balanceBefore.toUsdn);
            }

            assert(validator.balance == balanceBefore.validatorETH + securityDeposit);

            assert(usdn.sharesOf(address(usdnProtocol)) == balanceBefore.usdnProtocolUsdn);

            assert(wsteth.balanceOf(msg.sender) == balanceBefore.senderWstETH);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balanceBefore.usdnProtocolWstETH);
            assert(wsteth.balanceOf(validator) == balanceBefore.validatorWstETH);
            assert(wsteth.balanceOf(pendingAction.to) == balanceBefore.toWstETH);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_DEPOSIT_ERRORS);
        }
    }

    function validateWithdrawal(uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(currentPrice);

        ValidateWithdrawalBalanceBefore memory balanceBefore = ValidateWithdrawalBalanceBefore({
            senderETH: address(msg.sender).balance,
            senderWstETH: wsteth.balanceOf(msg.sender),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolUsdn: usdn.sharesOf(address(usdnProtocol)),
            usdnProtocolWstETH: wsteth.balanceOf(address(usdnProtocol))
        });
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(validator);

        vm.prank(msg.sender);
        try usdnProtocol.validateWithdrawal(validator, priceData, EMPTY_PREVIOUS_DATA) returns (bool success_) {
            assert(address(msg.sender).balance == balanceBefore.senderETH + action.securityDepositValue);
            if (success_) {
                assert(wsteth.balanceOf(msg.sender) >= balanceBefore.senderWstETH);

                assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH - action.securityDepositValue);
                assert(usdn.sharesOf(address(usdnProtocol)) < balanceBefore.usdnProtocolUsdn);
                assert(wsteth.balanceOf(address(usdnProtocol)) <= balanceBefore.usdnProtocolWstETH);
            } else {
                assert(wsteth.balanceOf(msg.sender) == balanceBefore.senderWstETH);

                assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH);
                assert(usdn.sharesOf(address(usdnProtocol)) == balanceBefore.usdnProtocolUsdn);
                assert(wsteth.balanceOf(address(usdnProtocol)) == balanceBefore.usdnProtocolWstETH);
            }
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateOpen(uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        bytes memory priceData = abi.encode(currentPrice);

        uint256 validatorETH = address(validator).balance;
        uint256 senderWstETH = wsteth.balanceOf(msg.sender);
        uint256 usdnProtocolETH = address(usdnProtocol).balance;
        uint256 usdnProtocolWstETH = wsteth.balanceOf(address(usdnProtocol));

        uint256 securityDeposit = usdnProtocol.getUserPendingAction(validator).securityDepositValue;

        vm.prank(msg.sender);
        try usdnProtocol.validateOpenPosition(validator, priceData, EMPTY_PREVIOUS_DATA) returns (bool success) {
            if (success) {
                assert(address(validator).balance == validatorETH + securityDeposit);
                assert(address(usdnProtocol).balance == usdnProtocolETH - securityDeposit);
            } else {
                assert(address(validator).balance == validatorETH);
                assert(address(usdnProtocol).balance == usdnProtocolETH);
            }
            assert(wsteth.balanceOf(address(usdnProtocol)) == usdnProtocolWstETH);
            assert(wsteth.balanceOf(msg.sender) == senderWstETH);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
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
            assert(usdnProtocol.getOpenExpoImbalanceLimitBps() == newOpenLimitBps);
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
