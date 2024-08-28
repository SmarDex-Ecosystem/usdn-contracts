// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Setup } from "../Setup.sol";
import { Utils } from "../helpers/Utils.sol";

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract FuzzActions is Setup, Utils {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice PROTCL-0
     */
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

        address payable dest = boundDestination(destinationsToken[address(usdn)], users, false, destRand);

        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceData);
        (, uint256 wstethPendingActions) = _getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, abi.encode(priceData), previousActionsData
        ) {
            //            uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();
            //
            //            assert(
            //                address(msg.sender).balance
            //                    == balancesBefore.senderEth - securityDeposit + lastAction.securityDepositValue
            //            );
            //            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountWstETHRand);
            //            assert(sdex.balanceOf(msg.sender) < balancesBefore.senderSdex);
            //            assert(
            //                address(usdnProtocol).balance
            //                    == balancesBefore.protocolEth + securityDeposit - lastAction.securityDepositValue
            //            );
            //            assert(
            //                wsteth.balanceOf(address(usdnProtocol))
            //                    == balancesBefore.protocolWsteth + amountWstETHRand - wstethPendingActions
            //            );
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_DEPOSIT_ERRORS);
        }
    }

    /**
     * @notice PROTCL-1
     */
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

        address payable dest = boundDestination(destinationsToken[address(wsteth)], users, false, destRand);
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceData);
        (int256 usdnPendingActions,) = _getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.initiateWithdrawal{ value: ethRand }(
            usdnShares, dest, validator, abi.encode(priceData), previousActionsData
        ) {
            //            uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();
            //
            //            assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);
            //            assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares - usdnShares);
            //
            //            assert(
            //                address(usdnProtocol).balance
            //                    == balancesBefore.protocolEth + securityDeposit - lastAction.securityDepositValue
            //            );
            //            assert(
            //                usdn.sharesOf(address(usdnProtocol))
            //                    == uint256(int256(balancesBefore.protocolUsdnShares) + int152(usdnShares) +
            // usdnPendingActions)
            //            );
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_WITHDRAWAL_ERRORS);
        }
    }

    /**
     * @notice PROTCL-2
     */
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
        address[] memory contractRecipients = new address[](1);
        contractRecipients[0] = address(usdnProtocol);
        address payable dest = boundDestination(contractRecipients, users, false, destRand);
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address validator = users[validatorRand];
        priceRand = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, dest);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceRand);
        (, uint256 wstethPendingActions) = _getTokenFromPendingAction(lastAction, priceRand);

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

            //            assert(
            //                address(usdnProtocol).balance
            //                    == balancesBefore.protocolEth + usdnProtocol.getSecurityDepositValue() -
            // lastAction.securityDepositValue
            //            );
            //            assert(
            //                address(msg.sender).balance
            //                    == balancesBefore.senderEth - usdnProtocol.getSecurityDepositValue() +
            // lastAction.securityDepositValue
            //            );
            //
            //            assert(
            //                wsteth.balanceOf(address(usdnProtocol))
            //                    == balancesBefore.protocolWsteth + amountRand - wstethPendingActions
            //            );
            //            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth - amountRand);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }

    /**
     * @notice PROTCL-3
     */
    function initiateClosePosition(
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand,
        uint256 amountToClose,
        uint256 posIdsIndexRand
    ) public {
        vm.deal(msg.sender, ethRand);

        address payable dest = boundDestination(destinationsToken[address(wsteth)], users, false, destRand);
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
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

                //                assert(address(msg.sender).balance == balancesBefore.senderEth - securityDeposit);
                //                assert(
                //                    uint8(usdnProtocol.getUserPendingAction(validator).action)
                //                        == uint8(IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition)
                //                );
                //                assert(address(usdnProtocol).balance == balancesBefore.protocolEth + securityDeposit);
            } else {
                //                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
            }

            //            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
            //            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_CLOSE_ERRORS);
        }
    }

    /**
     * @notice PROTCL-4
     */
    function validateDeposit(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        IUsdnProtocolTypes.DepositPendingAction memory pendingAction =
            usdnProtocol.i_toDepositPendingAction(usdnProtocol.getUserPendingAction(validator));
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceData);
        (int256 usdnPendingActions, uint256 wstethPendingActions) = _getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateDeposit(validator, abi.encode(priceData), previousActionsData) returns (bool success_)
        {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            if (success_) {
                //todo maybe determine the exact amount if it can be know before the call
                //                assert(usdn.sharesOf(pendingAction.to) > balancesBefore.toUsdnShares);
                //                if (pendingAction.to != msg.sender) {
                //                    assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares);
                //                }
                //                if (pendingAction.to != validator) {
                //                    assert(usdn.sharesOf(validator) == balancesBefore.validatorUsdnShares);
                //                }
            } else {
                //                assert(usdn.sharesOf(msg.sender) == balancesBefore.senderUsdnShares);
                //                assert(usdn.sharesOf(validator) == balancesBefore.validatorUsdnShares);
                //                assert(usdn.sharesOf(pendingAction.to) == balancesBefore.toUsdnShares);
            }

            //            assert(validator.balance == balancesBefore.validatorEth + securityDeposit);
            //
            //            assert(
            //                usdn.sharesOf(address(usdnProtocol))
            //                    == uint256(int256(balancesBefore.protocolUsdnShares) + usdnPendingActions)
            //            );
            //
            //            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
            //            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth -
            // wstethPendingActions);
            //            assert(wsteth.balanceOf(validator) == balancesBefore.validatorWsteth);
            //            assert(wsteth.balanceOf(pendingAction.to) == balancesBefore.toWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_DEPOSIT_ERRORS);
        }
    }

    /**
     * @notice PROTCL-5
     */
    function validateWithdrawal(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(validator);
        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceData);
        (int256 usdnPendingActions, uint256 wstethPendingActions) = _getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateWithdrawal(validator, abi.encode(priceData), previousActionsData) returns (
            bool success_
        ) {
            assert(address(msg.sender).balance == balancesBefore.senderEth + action.securityDepositValue);
            if (success_) {
                //                assert(wsteth.balanceOf(msg.sender) >= balancesBefore.senderWsteth);
                //                assert(address(usdnProtocol).balance == balancesBefore.protocolEth -
                // action.securityDepositValue);
                //                assert(
                //                    usdn.sharesOf(address(usdnProtocol))
                //                        < uint256(int256(balancesBefore.protocolUsdnShares) + usdnPendingActions)
                //                );
                //                assert(wsteth.balanceOf(address(usdnProtocol)) <= balancesBefore.protocolWsteth -
                // wstethPendingActions);
            } else {
                //                assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
                //                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
                //                assert(
                //                    usdn.sharesOf(address(usdnProtocol))
                //                        == uint256(int256(balancesBefore.protocolUsdnShares) + usdnPendingActions)
                //                );
                //                assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth -
                // wstethPendingActions);
            }
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_WITHDRAWAL_ERRORS);
        }
    }

    /**
     * @notice PROTCL-6
     */
    function validateOpenPosition(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);
        uint64 securityDeposit = usdnProtocol.getUserPendingAction(validator).securityDepositValue;

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);

        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceData);
        (, uint256 wstethPendingActions) = _getTokenFromPendingAction(lastAction, priceData);

        vm.prank(msg.sender);
        try usdnProtocol.validateOpenPosition(validator, abi.encode(priceData), previousActionsData) returns (
            bool success
        ) {
            if (success) {
                //                assert(
                //                    address(validator).balance
                //                        == balancesBefore.validatorEth + securityDeposit +
                // lastAction.securityDepositValue
                //                );
                //                assert(
                //                    address(usdnProtocol).balance
                //                        == balancesBefore.protocolEth - securityDeposit -
                // lastAction.securityDepositValue
                //                );
            } else {
                //                assert(address(validator).balance == balancesBefore.validatorEth);
                //                assert(address(usdnProtocol).balance == balancesBefore.protocolEth);
            }
            //            assert(wsteth.balanceOf(address(usdnProtocol)) == balancesBefore.protocolWsteth -
            // wstethPendingActions);
            //            assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_OPEN_ERRORS);
        }
    }

    /**
     * @notice PROTCL-7
     */
    function validateClosePosition(uint256 validatorRand, uint256 priceRand) public {
        validatorRand = bound(validatorRand, 0, users.length - 1);
        address payable validator = payable(users[validatorRand]);
        uint256 priceData = bound(priceRand, 0, type(uint128).max);

        IUsdnProtocolTypes.LongPendingAction memory longAction =
            usdnProtocol.i_toLongPendingAction(usdnProtocol.getUserPendingAction(validator));

        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            ,
            IUsdnProtocolTypes.PendingAction memory lastAction,
        ) = _getPreviousActionsData(msg.sender, priceData);
        (, uint256 wstethPendingActions) = _getTokenFromPendingAction(lastAction, priceData);

        uint256 securityDeposit = longAction.securityDepositValue;
        uint256 closeAmount = longAction.closeAmount;
        address to = longAction.to;

        BalancesSnapshot memory balancesBefore = getBalances(validator, msg.sender);

        vm.prank(msg.sender);
        try usdnProtocol.validateClosePosition(validator, abi.encode(priceData), previousActionsData) returns (
            bool success
        ) {
            if (success) {
                //                assert(msg.sender.balance == balancesBefore.senderEth + securityDeposit);
                //                assert(address(usdnProtocol).balance == balancesBefore.protocolEth - securityDeposit);
                //                assert(
                //                    wsteth.balanceOf(address(usdnProtocol)) < balancesBefore.protocolWsteth -
                // wstethPendingActions
                //                        && wsteth.balanceOf(address(usdnProtocol))
                //                            > balancesBefore.protocolWsteth - closeAmount - wstethPendingActions
                //                );
                //                assert(
                //                    wsteth.balanceOf(to) < balancesBefore.toWsteth + closeAmount
                //                        && wsteth.balanceOf(to) > balancesBefore.toWsteth
                //                );
                //                if (msg.sender != address(validator)) {
                //                    assert(validator.balance == balancesBefore.validatorEth);
                //                }
                //                if (msg.sender != to) {
                //                    assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
                //                }
                //                if (to != address(validator)) {
                //                    assert(to.balance == balancesBefore.toEth);
                //                    assert(wsteth.balanceOf(validator) == balancesBefore.validatorWsteth);
                //                }
            } else {
                //                assert(msg.sender.balance == balancesBefore.senderEth);
                //                assert(address(usdnProtocol).balance <= balancesBefore.protocolEth -
                // wstethPendingActions);
                //                assert(validator.balance == balancesBefore.validatorEth);
                //                assert(to.balance == balancesBefore.toEth);
                //                assert(wsteth.balanceOf(msg.sender) == balancesBefore.senderWsteth);
                //                assert(wsteth.balanceOf(to) == balancesBefore.toWsteth);
                //                assert(wsteth.balanceOf(validator) == balancesBefore.validatorWsteth);
            }
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_WITHDRAWAL_ERRORS);
        }
    }

    /**
     * @notice PROTCL-8
     */
    function validatePendingActions(uint256 maxValidations, uint256 priceRand) public {
        uint256 balanceBefore = address(msg.sender).balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        priceRand = bound(priceRand, 0, type(uint128).max);

        (
            IUsdnProtocolTypes.PreviousActionsData memory previousActionsData,
            uint256 securityDeposit,
            ,
            uint256 actionsLength
        ) = _getPreviousActionsData(msg.sender, priceRand);

        vm.prank(msg.sender);
        try usdnProtocol.validateActionablePendingActions(previousActionsData, maxValidations) returns (
            uint256 validatedActions
        ) {
            //            assert(
            //                actionsLength < maxValidations ? validatedActions == actionsLength : validatedActions ==
            // maxValidations
            //            );
            //            assert(address(msg.sender).balance == balanceBefore + securityDeposit);
            //            assert(address(usdnProtocol).balance == balanceBeforeProtocol - securityDeposit);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_CLOSE_ERRORS);
        }
    }

    /**
     * @notice PROTCL-9
     */
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

    /**
     * @notice PROTCL-10
     */
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

    /**
     * @notice PROTCL-11
     */
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

    /**
     * @notice PROTCL-12
     */
    function fullClosePosition(
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 priceRand,
        uint256 amountToClose,
        uint256 posIdsIndexRand
    ) public {
        initiateClosePosition(ethRand, destRand, validatorRand, priceRand, amountToClose, posIdsIndexRand);
        skip(usdnProtocol.getValidationDeadline() + 1);
        validateClosePosition(validatorRand, priceRand);
    }

    /**
     * @notice PROTCL-14
     */
    function liquidate(uint256 priceRand, uint256 iterationsRand, uint256 validationCost) public {
        vm.deal(msg.sender, validationCost);

        priceRand = bound(priceRand, 0, type(uint128).max);
        uint16 iterations = uint16(bound(iterationsRand, 1, type(uint16).max));
        bytes memory priceData = abi.encode(uint128(priceRand));
        uint256 wstethBeforeLiquidateProtocol = wsteth.balanceOf(address(usdnProtocol));
        uint256 ethBeforeLiquidateProtocol = address(usdnProtocol).balance;

        vm.prank(msg.sender);
        try usdnProtocol.liquidate{ value: validationCost }(priceData, iterations) {
            // assert(wsteth.balanceOf(address(usdnProtocol)) == wstethBeforeLiquidateProtocol);
            // assert(address(usdnProtocol).balance == ethBeforeLiquidateProtocol);
        } catch (bytes memory err) {
            _checkErrors(err, LIQUIDATE_ERRORS);
        }
    }

    function _getPreviousActionsData(address user, uint256 currentPrice)
        internal
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

    /**
     * @dev Returns the amount of USDN shares and WstETH that will be transferred in the next action
     * @param action The pending action
     * @param price The current price
     * @return usdn_ The amount of USDN shares
     * @return wsteth_ The amount of WstETH
     */
    function _getTokenFromPendingAction(IUsdnProtocolTypes.PendingAction memory action, uint256 price)
        internal
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
