// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract FuzzActions is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initiateDeposit(
        uint128 amountWstETHRand,
        uint128 amountSdexRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand
    ) public {
        wsteth.mintAndApprove(msg.sender, amountWstETHRand, address(usdnProtocol), amountWstETHRand);
        sdex.mintAndApprove(msg.sender, amountSdexRand, address(usdnProtocol), amountSdexRand);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, abi.encode(priceData), previousActionsData
        ) {
            uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();
            (, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);

            assert(
                address(msg.sender).balance
                    == balancesBefore.senderEth - securityDeposit + lastAction.securityDepositValue
            );
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountWstETHRand);
            assert(sdex.balanceOf(msg.sender) < balancesBefore.senderSdex);
            assert(
                address(usdnProtocol).balance
                    == balancesBefore.protocolEth + securityDeposit - lastAction.securityDepositValue
            );
            assert(
                wsteth.balanceOf(address(usdnProtocol))
                    == balancesBefore.protocolWsteth + amountWstETHRand - wstethPendingActions
            );
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
        uint256 priceRand
    ) public {
        wsteth.mintAndApprove(msg.sender, amountRand, address(usdnProtocol), amountRand);
        uint256 destRandBounded = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        vm.deal(msg.sender, ethRand);

        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address dest = destinationsToken[address(wsteth)][destRandBounded];
        address validator = validators[validatorRand];
        priceRand = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceRand);

        vm.prank(msg.sender);
        try usdnProtocol.initiateOpenPosition{ value: ethRand }(
            amountRand,
            liquidationPriceRand,
            dest,
            payable(validator),
            NO_PERMIT2,
            abi.encode(priceRand),
            previousActionsData
        ) returns (bool, IUsdnProtocolTypes.PositionId memory posId) {
            posIds.push(posId);
            (, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceRand);

            assert(
                address(usdnProtocol).balance
                    == balancesBefore.protocolEth + usdnProtocol.getSecurityDepositValue() - lastAction.securityDepositValue
            );
            assert(
                address(msg.sender).balance
                    == balancesBefore.senderEth - usdnProtocol.getSecurityDepositValue() + lastAction.securityDepositValue
            );

            assert(
                wsteth.balanceOf(address(usdnProtocol))
                    == balancesBefore.protocolWsteth + amountRand - wstethPendingActions
            );
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
        uint256 priceRand
    ) public {
        vm.prank(msg.sender);
        usdn.approve(address(usdnProtocol), usdnShares);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.initiateWithdrawal{ value: ethRand }(
            usdnShares, dest, validator, abi.encode(priceData), previousActionsData
        ) {
            uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();
            (int256 usdnPendingActions,) = getTokenFromPendingAction(lastAction, priceData);

            assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);
            assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares - usdnShares);

            assert(
                address(usdnProtocol).balance
                    == balancesBefore.protocolEth + securityDeposit - lastAction.securityDepositValue
            );
            assert(
                usdn.sharesOf(address(usdnProtocol))
                    == uint256(int256(balancesBefore.protocolUsdnShares) + int152(usdnShares) + usdnPendingActions)
            );
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateDeposit(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        IUsdnProtocolTypes.DepositPendingAction memory pendingAction =
            usdnProtocol.i_toDepositPendingAction(usdnProtocol.getUserPendingAction(validator));
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateDeposit(validator, abi.encode(priceData), previousActionsData) returns (bool success_)
        {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
            (int256 usdnPendingActions, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);

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

            assert(
                usdn.sharesOf(address(usdnProtocol))
                    == uint256(int256(balancesBefore.protocolUsdnShares) + usdnPendingActions)
            );

            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth - wstethPendingActions);
            assert(wsteth.balanceOf(validator) == balancesBefore.validatorWsteth);
            assert(wsteth.balanceOf(pendingAction.to) == balancesBefore.toWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_DEPOSIT_ERRORS);
        }
    }

    function validateWithdrawal(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(validator);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateWithdrawal(validator, abi.encode(priceData), previousActionsData) returns (
            bool success_
        ) {
            (int256 usdnPendingActions, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);
            assert(address(msg.sender).balance == balancesBefore.senderEth + action.securityDepositValue);
            if (success_) {
                assert(wsteth.balanceOf(msg.sender) >= balancesBefore.senderWsteth);

                assert(address(usdnProtocol).balance == balancesBefore.protocolEth - action.securityDepositValue);
                assert(
                    usdn.sharesOf(address(usdnProtocol))
                        < uint256(int256(balancesBefore.protocolUsdnShares) + usdnPendingActions)
                );
                assert(wsteth.balanceOf(address(usdnProtocol)) <= balancesBefore.protocolWsteth - wstethPendingActions);
            } else {
                assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
                assert(
                    usdn.sharesOf(address(usdnProtocol))
                        == uint256(int256(balancesBefore.protocolUsdnShares) + usdnPendingActions)
                );
                assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth - wstethPendingActions);
            }
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateOpen(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);
        uint64 securityDeposit = usdnProtocol.getUserPendingAction(validator).securityDepositValue;

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);

        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateOpenPosition(validator, abi.encode(priceData), previousActionsData) returns (
            bool success
        ) {
            if (success) {
                assert(
                    address(validator).balance
                        == balancesBefore.validatorEth + securityDeposit + lastAction.securityDepositValue
                );
                assert(
                    address(usdnProtocol).balance
                        == balancesBefore.protocolEth - securityDeposit - lastAction.securityDepositValue
                );
            } else {
                assert(address(validator).balance == balancesBefore.validatorEth);
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
            }
            (, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth - wstethPendingActions);
            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
        }
    }

    function validatePendingActions(uint256 maxValidations, uint256 priceRand) public {
        uint256 balanceBefore = address(msg.sender).balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        priceRand = bound(priceRand, 0, type(uint128).max);

        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            uint256 securityDeposit,
            ,
            uint256 actionsLength
        ) = getPreviousActionsData(msg.sender, priceRand);

        vm.prank(msg.sender);
        try usdnProtocol.validateActionablePendingActions(previousActionsData, maxValidations) returns (
            uint256 validatedActions
        ) {
            assert(
                actionsLength < maxValidations ? validatedActions == actionsLength : validatedActions == maxValidations
            );
            assert(address(msg.sender).balance == balanceBefore + securityDeposit);
            assert(address(usdnProtocol).balance == balanceBeforeProtocol - securityDeposit);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_PENDING_ACTIONS_ERRORS);
        }
    }

    function getPreviousActionsData(address user, uint256 currentPrice)
        public
        view
        returns (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData_,
            uint256 securityDeposit_,
            IUsdnProtocolTypes.PendingAction memory lastAction_,
            uint256 actionsLength_
        )
    {
        (IUsdnProtocolTypes.PendingAction[] memory actions, uint128[] memory rawIndices) =
            usdnProtocol.getActionablePendingActions(user);
        if (rawIndices.length == 0) {
            return (previousActionsData_, securityDeposit_, lastAction_, 0);
        }
        bytes[] memory priceData = new bytes[](rawIndices.length);
        for (uint256 i = 0; i < rawIndices.length; i++) {
            priceData[i] = abi.encode(currentPrice);
            securityDeposit_ += actions[i].securityDepositValue;
        }
        lastAction_ = actions[actions.length - 1];
        actionsLength_ = actions.length;
        previousActionsData_ = IUsdnProtocolTypes.PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });
    }

    function getTokenFromPendingAction(IUsdnProtocolTypes.PendingAction memory action, uint256 price)
        public
        view
        returns (int256 usdn_, uint256 wsteth_)
    {
        if (action.action == IUsdnProtocolTypes.ProtocolAction.ValidateDeposit) {
            IUsdnProtocolTypes.DepositPendingAction memory depositAction = usdnProtocol.i_toDepositPendingAction(action);
            (uint256 usdnSharesExpected,) =
                usdnProtocol.previewDeposit(depositAction.amount, depositAction.assetPrice, uint128(block.timestamp));
            return (int256(usdnSharesExpected), 0);
        } else if (action.action == IUsdnProtocolTypes.ProtocolAction.ValidateWithdrawal) {
            IUsdnProtocolTypes.WithdrawalPendingAction memory withdrawalAction =
                usdnProtocol.i_toWithdrawalPendingAction(action);
            uint256 amount =
                usdnProtocol.i_mergeWithdrawalAmountParts(withdrawalAction.sharesLSB, withdrawalAction.sharesMSB);
            uint256 assetToTransfer = usdnProtocol.previewWithdraw(amount, price, uint128(block.timestamp));
            return (-int256(amount), assetToTransfer);
        } else if (action.action == IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition) {
            return (usdn_, wsteth_);
        } else if (action.action == IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition) {
            IUsdnProtocolTypes.LongPendingAction memory longAction = usdnProtocol.i_toLongPendingAction(action);
            return (0, longAction.closeAmount);
        } else {
            return (usdn_, wsteth_);
        }
    }
}
