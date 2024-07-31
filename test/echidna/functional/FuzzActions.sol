// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract FuzzActions is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    /// @custom:property PROTCL-1 When initializing an action, the sender pay the security deposit
    /// @custom:property PROTCL-2 When initializing an action, the protocol receive the security deposit
    /// @custom:property PROTCL-3 When initializing an action, the sender pay the amount of wstETH defined
    /// @custom:property PROTCL-4 When initializing an action, the protocol receive the amount of wstETH defined
    /// @custom:property VAULT-1 When an user initialize a deposit, msg.sender pay some SDEX
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
        (, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, abi.encode(priceData), previousActionsData
        ) {
            _checkBalancesETH(balancesBefore, lastAction);
            _checkBalancesWstETH(balancesBefore, amountWstETHRand, wstethPendingActions);
            assertLt(sdex.balanceOf(msg.sender), balancesBefore.senderSdex, "VAULT-1");
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_DEPOSIT_ERRORS);
        }
    }

    /// @custom:property PROTCL-1 When initializing an action, the sender pay the security deposit
    /// @custom:property PROTCL-2 When initializing an action, the protocol receive the security deposit
    /// @custom:property VAULT-2 When an user initialize a withdraw, msg.sender pay the amount of usdn shares defined
    /// @custom:property VAULT-3 When an user initialize a withdraw, protocol receive the amount of usdn shares defined
    /// @custom:property VAULT-4 An user can't initialize a withdraw with zero shares
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
        (int256 usdnPendingActions,) = getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.initiateWithdrawal{ value: ethRand }(
            usdnShares, dest, validator, abi.encode(priceData), previousActionsData
        ) {
            _checkBalancesETH(balancesBefore, lastAction);

            assertGt(usdnShares, 0, "VAULT-6");
            assertEq(usdn.sharesOf(msg.sender), balancesBefore.senderUsdnShares - usdnShares, "VAULT-4");

            assertEq(
                usdn.sharesOf(address(usdnProtocol)),
                uint256(int256(balancesBefore.protocolUsdnShares) + int152(usdnShares) + usdnPendingActions),
                "VAULT-5"
            );
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_WITHDRAWAL_ERRORS);
        }
    }

    /// @custom:property PROTCL-1 When initializing an action, the sender pay the security deposit
    /// @custom:property PROTCL-2 When initializing an action, the protocol receive the security deposit
    /// @custom:property PROTCL-3 When initializing an action, the sender pay the amount of wstETH defined
    /// @custom:property PROTCL-4 When initializing an action, the protocol receive the amount of wstETH defined
    function initiateOpenPosition(
        uint128 amountRand,
        uint128 liquidationPriceRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand
    ) public {
        wsteth.mintAndApprove(msg.sender, amountRand, address(usdnProtocol), amountRand);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address validator = validators[validatorRand];
        priceRand = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = getPreviousActionsData(msg.sender, priceRand);
        (, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceRand);

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

            _checkBalancesETH(balancesBefore, lastAction);
            _checkBalancesWstETH(balancesBefore, amountRand, wstethPendingActions);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }

    function initiateClosePosition(
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand,
        uint256 amountToClose,
        uint256 posIdsIndexRand
    ) public {
        vm.deal(msg.sender, ethRand);
        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);
        priceRand = bound(priceRand, 0, type(uint128).max);
        bytes memory priceData = abi.encode(uint128(priceRand));
        amountToClose = bound(amountToClose, 0, type(uint128).max);

        IUsdnProtocolTypes.PositionId memory posId;
        uint256 posIdsIndex;
        if (posIds.length > 0) {
            posIdsIndex = bound(posIdsIndexRand, 0, posIds.length - 1);
            posId = posIds[posIdsIndex];
        }

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);

        vm.prank(msg.sender);
        try usdnProtocol.initiateClosePosition{ value: ethRand }(
            posId, uint128(amountToClose), dest, validator, priceData, EMPTY_PREVIOUS_DATA
        ) returns (bool success_) {
            if (success_) {
                uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();

                // remove the position
                posIds[posIdsIndex] = posIds[posIds.length - 1];
                posIds.pop();

                assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);
                assert(
                    uint8(usdnProtocol.getUserPendingAction(validator).action)
                        == uint8(IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition)
                );
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth + securityDeposit);
            } else {
                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
            }

            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_CLOSE_ERRORS);
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
        (int256 usdnPendingActions, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateDeposit(validator, abi.encode(priceData), previousActionsData) returns (bool success_)
        {
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
        (int256 usdnPendingActions, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateWithdrawal(validator, abi.encode(priceData), previousActionsData) returns (
            bool success_
        ) {
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

    function validateOpenPosition(uint256 validatorRand, uint256 priceRand) public {
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
        (, uint256 wstethPendingActions) = getTokenFromPendingAction(lastAction, priceData);

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

    function fullDeposit(
        uint128 amountWstETHRand,
        uint128 amountSdexRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand
    ) public {
        initiateDeposit(amountWstETHRand, amountSdexRand, ethRand, destRand, validatorRand, priceRand);
        skip(usdnProtocol.getValidationDeadline() + 1);
        validateDeposit(validatorRand, priceRand);
    }

    function fullWithdrawal(
        uint152 usdnShares,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand
    ) public {
        initiateWithdrawal(usdnShares, ethRand, destRand, validatorRand, priceRand);
        skip(usdnProtocol.getValidationDeadline() + 1);
        validateWithdrawal(validatorRand, priceRand);
    }

    function fullOpenPosition(
        uint128 amountRand,
        uint128 liquidationPriceRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand
    ) public {
        initiateOpenPosition(amountRand, liquidationPriceRand, ethRand, destRand, validatorRand, priceRand);
        skip(usdnProtocol.getValidationDeadline() + 1);
        validateOpenPosition(validatorRand, priceRand);
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

    function _checkBalancesETH(
        BalancesSnapshot memory balancesBefore,
        IUsdnProtocolTypes.PendingAction memory lastAction
    ) internal view {
        assertEq(
            address(msg.sender).balance,
            balancesBefore.senderEth - usdnProtocol.getSecurityDepositValue() + lastAction.securityDepositValue,
            "PROTCL-1"
        );
        assertEq(
            address(usdnProtocol).balance,
            balancesBefore.protocolEth + usdnProtocol.getSecurityDepositValue() - lastAction.securityDepositValue,
            "PROTCL-2"
        );
    }

    function _checkBalancesWstETH(BalancesSnapshot memory balancesBefore, uint256 amount, uint256 wstethPendingActions)
        internal
        view
    {
        assertEq(wsteth.balanceOf(msg.sender), balancesBefore.senderWsteth - amount, "PROTCL-3");
        assertEq(
            wsteth.balanceOf(address(usdnProtocol)),
            balancesBefore.protocolWsteth + amount - wstethPendingActions,
            "PROTCL-4"
        );
    }
}
