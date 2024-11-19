// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IOwnershipCallback } from "../../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolActionsUtilsLibrary {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using SafeCast for uint256;
    using SignedMath for int256;

    /**
     * @notice Data structure for the transient state of the `_validateMultipleActionable` function
     * @param pending The candidate pending action to validate
     * @param frontRawIndex The raw index of the front of the queue
     * @param rawIndex The raw index of the candidate pending action
     * @param executed Whether the pending action was executed
     * @param liq Whether the pending action was liquidated
     */
    struct ValidateMultipleActionableData {
        Types.PendingAction pending;
        uint128 frontRawIndex;
        uint128 rawIndex;
        bool executed;
        bool liq;
    }

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function liquidate(bytes calldata currentPriceData)
        external
        returns (Types.LiqTickInfo[] memory liquidatedTicks_)
    {
        uint256 balanceBefore = address(this).balance;
        PriceInfo memory currentPrice = Utils._getOraclePrice(Types.ProtocolAction.Liquidation, 0, "", currentPriceData);

        (liquidatedTicks_,) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            Constants.MAX_LIQUIDATION_ITERATION,
            Types.ProtocolAction.Liquidation,
            currentPriceData
        );

        Utils._refundExcessEther(0, 0, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions}
    function validateActionablePendingActions(
        Types.PreviousActionsData calldata previousActionsData,
        uint256 maxValidations
    ) external returns (uint256 validatedActions_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (validatedActions_, amountToRefund) = _validateMultipleActionable(previousActionsData, maxValidations);

        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions}
    function transferPositionOwnership(
        Types.PositionId calldata posId,
        address newOwner,
        bytes calldata delegationSignature,
        bytes32 domainSeparatorV4
    ) external {
        Types.Storage storage s = Utils._getMainStorage();

        (bytes32 tickHash, uint256 version) = Utils._tickHash(posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        Types.Position storage pos = s._longPositions[tickHash][posId.index];

        if (newOwner == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }

        if (msg.sender != pos.user) {
            if (delegationSignature.length == 0) {
                revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
            } else {
                _verifyTransferPositionOwnershipDelegation(
                    posId, pos.user, newOwner, delegationSignature, domainSeparatorV4
                );
            }
        }

        pos.user = newOwner;

        if (ERC165Checker.supportsInterface(newOwner, type(IOwnershipCallback).interfaceId)) {
            IOwnershipCallback(newOwner).ownershipCallback(msg.sender, posId);
        }

        emit IUsdnProtocolEvents.PositionOwnershipTransferred(posId, msg.sender, newOwner);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function getLongPosition(Types.PositionId memory posId)
        public
        view
        returns (Types.Position memory pos_, uint24 liquidationPenalty_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        (bytes32 tickHash, uint256 version) = Utils._tickHash(posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        pos_ = s._longPositions[tickHash][posId.index];
        liquidationPenalty_ = s._tickData[tickHash].liquidationPenalty;
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Update protocol balances, then prepare the data for the initiate close position action
     * @dev Reverts if the imbalance limit is reached, or if any of the checks in `_checkInitiateClosePosition` fail
     * Returns without creating a pending action if the position gets liquidated in this transaction
     * @param params The parameters for the _prepareClosePositionData function
     * @return data_ The close position data
     * @return liquidated_ Whether the position was liquidated and the caller should return early
     */
    function _prepareClosePositionData(Types.PrepareInitiateClosePositionParams calldata params)
        public
        returns (Types.ClosePositionData memory data_, bool liquidated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        (data_.pos, data_.liquidationPenalty) = getLongPosition(params.posId);

        _checkInitiateClosePosition(data_.pos, params);

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.InitiateClosePosition,
            block.timestamp,
            Utils._calcActionId(params.validator, uint128(block.timestamp)),
            params.currentPriceData
        );

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.InitiateClosePosition,
            params.currentPriceData
        );

        uint256 version = s._tickVersion[params.posId.tick];
        if (version != params.posId.tickVersion) {
            // the current tick version doesn't match the version from the position,
            // that means that the position has been liquidated in this transaction
            return (data_, true);
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        data_.lastPrice = s._lastPrice;
        // add the position fee
        uint256 adjustedPrice =
            (data_.lastPrice - data_.lastPrice * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();
        if (adjustedPrice < params.userMinPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolSlippageMinPriceExceeded();
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * params.amountToClose / data_.pos.amount).toUint128();
        data_.longTradingExpo = Core.longTradingExpoWithFunding(data_.lastPrice, uint128(block.timestamp));
        data_.liqMulAcc = s._liqMultiplierAccumulator;

        // the approximate value position to remove is calculated with `_lastPrice`, so not taking into account
        // any fees. This way, the removal of the position doesn't affect the liquidation multiplier calculations

        // to have maximum precision, we do not pre-compute the liquidation multiplier with a fixed
        // precision just now, we will store it in the pending action later, to be used in the validate action
        int24 tick = Utils._calcTickWithoutPenalty(params.posId.tick, data_.liquidationPenalty);
        uint128 liqPriceWithoutPenalty =
            Utils._getEffectivePriceForTick(tick, data_.lastPrice, data_.longTradingExpo, data_.liqMulAcc);

        uint256 balanceLong = s._balanceLong;

        data_.tempPositionValue =
            _assetToRemove(balanceLong, data_.lastPrice, liqPriceWithoutPenalty, data_.totalExpoToClose);

        // we perform the imbalance check with the full position value subtracted from the long side, which is
        // representative of the state of the balances after this initiate action
        _checkImbalanceLimitClose(data_.totalExpoToClose, data_.tempPositionValue);
    }

    /**
     * @notice Validate multiple actionable pending actions
     * @param previousActionsData The data for the actions to validate (price and raw indices)
     * @param maxValidations The maximum number of validations to perform
     * @return validatedActions_ The number of validated actions
     * @return amountToRefund_ The total amount of security deposits refunded
     */
    function _validateMultipleActionable(Types.PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        internal
        returns (uint256 validatedActions_, uint256 amountToRefund_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 length = previousActionsData.rawIndices.length;
        if (previousActionsData.priceData.length != length || length < 1) {
            return (0, 0);
        }
        if (maxValidations > length) {
            maxValidations = length;
        }
        uint128 lowLatencyDeadline = s._lowLatencyValidatorDeadline;
        uint16 middlewareLowLatencyDelay = s._oracleMiddleware.getLowLatencyDelay();
        uint128 onChainDeadline = s._onChainValidatorDeadline;
        uint256 i;
        do {
            if (s._pendingActionsQueue.empty()) {
                break;
            }
            ValidateMultipleActionableData memory data; // avoid stack too deep
            // perform cleanup on the queue if needed
            (data.pending, data.frontRawIndex) = s._pendingActionsQueue.front();
            if (data.pending.timestamp == 0) {
                s._pendingActionsQueue.popFront();
            }

            // check if the pending action is actionable and validate it
            data.rawIndex = previousActionsData.rawIndices[i];
            if (data.rawIndex != data.frontRawIndex) {
                // only get the pending action if we didn't already get it via `front` above
                if (!s._pendingActionsQueue.isValid(data.rawIndex)) {
                    // the raw index is not in the queue, let's keep looking
                    unchecked {
                        i++;
                    }
                    continue;
                }
                data.pending = s._pendingActionsQueue.atRaw(data.rawIndex);
            }
            if (_isActionable(data.pending.timestamp, lowLatencyDeadline, middlewareLowLatencyDelay, onChainDeadline)) {
                if (data.pending.action == Types.ProtocolAction.ValidateDeposit) {
                    data.executed = Vault._validateDepositWithAction(data.pending, previousActionsData.priceData[i]);
                } else if (data.pending.action == Types.ProtocolAction.ValidateWithdrawal) {
                    data.executed = Vault._validateWithdrawalWithAction(data.pending, previousActionsData.priceData[i]);
                } else if (data.pending.action == Types.ProtocolAction.ValidateOpenPosition) {
                    (data.executed, data.liq,) =
                        ActionsLong._validateOpenPositionWithAction(data.pending, previousActionsData.priceData[i]);
                } else if (data.pending.action == Types.ProtocolAction.ValidateClosePosition) {
                    (data.executed, data.liq) =
                        ActionsLong._validateClosePositionWithAction(data.pending, previousActionsData.priceData[i]);
                }
            } else {
                // not actionable or empty pending action, let's keep looking
                unchecked {
                    i++;
                }
                continue;
            }
            if (data.executed || data.liq) {
                // validation was performed, let's update the return values and cleanup
                Utils._clearPendingAction(data.pending.validator, data.rawIndex);
                amountToRefund_ += data.pending.securityDepositValue;
                unchecked {
                    validatedActions_++;
                }
                emit IUsdnProtocolEvents.SecurityDepositRefunded(
                    data.pending.validator, msg.sender, data.pending.securityDepositValue
                );
            } else {
                // if we didn't perform a validation, this likely means that there are pending liquidations, we stop
                break;
            }
            unchecked {
                i++;
            }
        } while (i < maxValidations);
    }

    /**
     * @notice Check whether a pending action is actionable, i.e any user can validate it and retrieve the security
     * deposit
     * @dev Between `initiateTimestamp` and `initiateTimestamp + lowLatencyDeadline`,
     * the validator receives the security deposit
     * Between `initiateTimestamp + lowLatencyDelay` and `initiateTimestamp + lowLatencyDelay + onChainDeadline`,
     * the validator also receives the security deposit
     * Outside of those periods, the security deposit goes to the user validating the pending action
     * @param initiateTimestamp The timestamp at which the action was initiated
     * @param lowLatencyDeadline The deadline after which the action is actionable within a low latency oracle
     * @param lowLatencyDelay The amount of time the action can be validated with a low latency oracle
     * @param onChainDeadline The deadline after which the action is actionable with an on-chain oracle
     * @return actionable_ Whether the pending action is actionable
     */
    function _isActionable(
        uint256 initiateTimestamp,
        uint256 lowLatencyDeadline,
        uint256 lowLatencyDelay,
        uint256 onChainDeadline
    ) internal view returns (bool actionable_) {
        if (initiateTimestamp == 0) {
            return false;
        }
        if (block.timestamp <= initiateTimestamp + lowLatencyDelay) {
            // the validation must happen with a low-latency oracle
            actionable_ = block.timestamp > initiateTimestamp + lowLatencyDeadline;
        } else {
            // the validation must happen with an on-chain oracle
            actionable_ = block.timestamp > initiateTimestamp + lowLatencyDelay + onChainDeadline;
        }
    }

    /**
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on the vault side, otherwise revert
     * @param posTotalExpoToClose The total expo to remove position
     * @param posValueToClose The value to remove from the position (and the long balance)
     */
    function _checkImbalanceLimitClose(uint256 posTotalExpoToClose, uint256 posValueToClose) internal view {
        Types.Storage storage s = Utils._getMainStorage();

        int256 closeExpoImbalanceLimitBps;
        if (msg.sender == address(s._rebalancer)) {
            closeExpoImbalanceLimitBps = s._rebalancerCloseExpoImbalanceLimitBps;
        } else {
            closeExpoImbalanceLimitBps = s._closeExpoImbalanceLimitBps;
        }

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongBalance = s._balanceLong.toInt256().safeSub(posValueToClose.toInt256());
        uint256 newTotalExpo = s._totalExpo - posTotalExpoToClose;
        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault);

        int256 imbalanceBps = Utils._calcImbalanceCloseBps(currentVaultExpo, newLongBalance, newTotalExpo);

        if (imbalanceBps > closeExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Perform checks for the initiate close position action
     * @dev Reverts if the to address is zero, the position was not validated yet, the position is not owned by the
     * user, the amount to close is higher than the position amount, or the amount to close is zero
     * @param pos The position to close
     * @param params The parameters for the {_prepareClosePositionData} function
     */
    function _checkInitiateClosePosition(
        Types.Position memory pos,
        Types.PrepareInitiateClosePositionParams calldata params
    ) internal {
        Types.Storage storage s = Utils._getMainStorage();

        if (params.to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (params.validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (!pos.validated) {
            revert IUsdnProtocolErrors.UsdnProtocolPositionNotValidated();
        }
        if (params.amountToClose == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }
        if (params.amountToClose > pos.amount) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountToCloseHigherThanPositionAmount(
                params.amountToClose, pos.amount
            );
        }

        if (msg.sender != pos.user) {
            if (params.delegationSignature.length == 0) {
                revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
            } else {
                _verifyInitiateCloseDelegation(params, pos.user);
            }
        }

        // make sure the remaining position is higher than _minLongPosition
        // for the Rebalancer, we allow users to close their position fully in every case
        uint128 remainingAmount = pos.amount - params.amountToClose;
        if (remainingAmount > 0 && remainingAmount < s._minLongPosition && msg.sender != address(s._rebalancer)) {
            revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
        }
    }

    /**
     * @notice Calculate how much assets must be removed from the long balance due to a position closing
     * @dev The amount is bound by the amount of assets available on the long side
     * @param balanceLong The balance of long positions (with asset decimals)
     * @param price The price to use for the position value calculation
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo to remove from the position
     * @return boundedPosValue_ The amount of assets to remove from the long balance, bound by zero and the available
     * long balance
     */
    function _assetToRemove(uint256 balanceLong, uint128 price, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        internal
        pure
        returns (uint256 boundedPosValue_)
    {
        // calculate position value
        int256 positionValue = Utils._positionValue(posExpo, price, liqPriceWithoutPenalty);

        if (positionValue <= 0) {
            // should not happen, unless we did not manage to liquidate all ticks that needed to be liquidated during
            // the initiateClosePosition
            boundedPosValue_ = 0;
        } else if (uint256(positionValue) > balanceLong) {
            boundedPosValue_ = balanceLong;
        } else {
            boundedPosValue_ = uint256(positionValue);
        }
    }

    /**
     * @notice Performs the {initiateClosePosition} EIP712 delegation signature verification
     * @dev Reverts if the function arguments don't match those included in the signature
     * and if the signer isn't the owner of the position
     * @param params The parameters for the {_prepareClosePositionData} function
     * @param positionOwner The position owner
     */
    function _verifyInitiateCloseDelegation(
        Types.PrepareInitiateClosePositionParams calldata params,
        address positionOwner
    ) internal {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 nonce = s._nonce[positionOwner];
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            params.domainSeparatorV4,
            keccak256(
                abi.encode(
                    Constants.INITIATE_CLOSE_TYPEHASH,
                    keccak256(abi.encode(params.posId)),
                    params.amountToClose,
                    params.userMinPrice,
                    params.to,
                    params.deadline,
                    positionOwner,
                    msg.sender,
                    nonce
                )
            )
        );

        if (ECDSA.recover(digest, params.delegationSignature) != positionOwner) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidDelegationSignature();
        }

        s._nonce[positionOwner] = nonce + 1;
    }

    /**
     * @notice Performs the {transferPositionOwnership} EIP712 delegation signature verification
     * @dev Reverts if the function arguments don't match those included in the signature
     * and if the signer isn't the owner of the position
     * @param posId The unique identifier of the position
     * @param positionOwner The current position owner
     * @param newPositionOwner The new position owner
     * @param delegationSignature An EIP712 signature that proves the caller is authorized by the owner of the position
     * to transfer the ownership to a different address on his behalf
     * @param domainSeparatorV4 The domain separator v4
     */
    function _verifyTransferPositionOwnershipDelegation(
        Types.PositionId calldata posId,
        address positionOwner,
        address newPositionOwner,
        bytes calldata delegationSignature,
        bytes32 domainSeparatorV4
    ) internal {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 nonce = s._nonce[positionOwner];
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domainSeparatorV4,
            keccak256(
                abi.encode(
                    Constants.TRANSFER_POSITION_OWNERSHIP_TYPEHASH,
                    keccak256(abi.encode(posId)),
                    positionOwner,
                    newPositionOwner,
                    msg.sender,
                    nonce
                )
            )
        );

        if (ECDSA.recover(digest, delegationSignature) != positionOwner) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidDelegationSignature();
        }

        s._nonce[positionOwner] = nonce + 1;
    }
}
