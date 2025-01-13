// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IPaymentCallback } from "../../interfaces/UsdnProtocol/IPaymentCallback.sol";
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

library UsdnProtocolVaultLibrary {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using SafeCast for uint256;
    using SafeTransferLib for address;
    using SignedMath for int256;

    /**
     * @dev Parameters for the internal {_initiateDeposit} function.
     * The user's input for the minimum amount of shares to receive is not guaranteed due to the price difference
     * between the initiate and validate actions.
     * @param user The address of the user initiating the deposit.
     * @param to The recipient of the USDN tokens.
     * @param validator The address that is supposed to validate the deposit and receive the security deposit.
     * @param amount The amount of assets to deposit.
     * @param sharesOutMin The minimum amount of USDN shares to receive.
     * @param securityDepositValue The value of the security deposit for the newly created deposit.
     */
    struct InitiateDepositParams {
        address user;
        address to;
        address validator;
        uint128 amount;
        uint256 sharesOutMin;
        uint64 securityDepositValue;
    }

    /**
     * @dev Structure to hold the transient data during {_initiateDeposit}.
     * @param lastPrice The last known price of the asset.
     * @param isLiquidationPending Whether some liquidations still need to be performed.
     * @param feeBps The vault deposit fee (in basis points).
     * @param totalExpo The total exposure of the long side.
     * @param balanceLong The balance of the long side.
     * @param balanceVault The balance of the vault including the funding.
     * @param usdnTotalShares Total minted shares of USDN.
     * @param sdexToBurn The required amount of SDEX to burn for the deposit.
     */
    struct InitiateDepositData {
        uint128 lastPrice;
        bool isLiquidationPending;
        uint16 feeBps;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 usdnTotalShares;
        uint256 sdexToBurn;
    }

    /**
     * @dev Parameters for the internal {_initiateWithdrawal} function.
     * @param user The address of the user initiating the withdrawal.
     * @param to The recipient of the assets.
     * @param validator The address that is supposed to validate the withdrawal and receive the security deposit.
     * @param usdnShares The amount of USDN shares to withdraw.
     * @param amountOutMin The minimum amount of assets to receive.
     * @param securityDepositValue The value of the security deposit for the newly created withdrawal.
     */
    struct WithdrawalParams {
        address user;
        address to;
        address validator;
        uint152 usdnShares;
        uint256 amountOutMin;
        uint64 securityDepositValue;
    }

    /**
     * @dev Structure to hold the transient data during {_initiateWithdrawal}.
     * @param usdnTotalShares The total supply of USDN shares.
     * @param totalExpo The current total exposure.
     * @param balanceLong The balance of the long side.
     * @param balanceVault The balance of the vault including the funding.
     * @param withdrawalAmountAfterFees The predicted amount of assets that will be withdrawn after fees.
     * @param lastPrice The last known price of the asset.
     * @param feeBps The vault deposit fee (in basis points).
     * @param isLiquidationPending Whether some liquidations still need to be performed.
     */
    struct WithdrawalData {
        uint256 usdnTotalShares;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 withdrawalAmountAfterFees;
        uint128 lastPrice;
        uint16 feeBps;
        bool isLiquidationPending;
    }

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions.initiateDeposit}.
    function initiateDeposit(
        uint128 amount,
        uint256 sharesOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        Types.Storage storage s = Utils._getMainStorage();

        if (deadline < block.timestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolDeadlineExceeded();
        }
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 validatorAmount;
        (validatorAmount, success_) = _initiateDeposit(
            InitiateDepositParams({
                user: msg.sender,
                to: to,
                validator: validator,
                amount: amount,
                sharesOutMin: sharesOutMin,
                securityDepositValue: securityDepositValue
            }),
            currentPriceData
        );

        uint256 amountToRefund;
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        // refund any securityDeposit from a stale pending action to the validator
        if (validatorAmount > 0) {
            if (validator != msg.sender) {
                balanceBefore -= validatorAmount;
                Utils._refundEther(validatorAmount, validator);
            } else {
                amountToRefund += validatorAmount;
            }
        }

        Utils._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions.validateDeposit}.
    function validateDeposit(
        address payable validator,
        bytes calldata depositPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _validateDeposit(validator, depositPriceData);
        uint256 securityDeposit;
        if (success_) {
            securityDeposit = _executePendingActionOrRevert(previousActionsData);
        }
        if (msg.sender != validator) {
            Utils._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = securityDeposit;
        } else {
            amountToRefund += securityDeposit;
        }
        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions.initiateWithdrawal}.
    function initiateWithdrawal(
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address payable validator,
        uint256 deadline,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        Types.Storage storage s = Utils._getMainStorage();

        if (deadline < block.timestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolDeadlineExceeded();
        }
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 validatorAmount;
        (validatorAmount, success_) = _initiateWithdrawal(
            WithdrawalParams({
                user: msg.sender,
                to: to,
                validator: validator,
                usdnShares: usdnShares,
                amountOutMin: amountOutMin,
                securityDepositValue: securityDepositValue
            }),
            currentPriceData
        );

        uint256 amountToRefund;
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(previousActionsData);
            }
        }

        // refund any securityDeposit from a stale pending action to the validator
        if (validatorAmount > 0) {
            if (validator != msg.sender) {
                balanceBefore -= validatorAmount;
                Utils._refundEther(validatorAmount, validator);
            } else {
                amountToRefund += validatorAmount;
            }
        }
        Utils._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolActions.validateWithdrawal}.
    function validateWithdrawal(
        address payable validator,
        bytes calldata withdrawalPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _validateWithdrawal(validator, withdrawalPriceData);
        uint256 securityDeposit;
        if (success_) {
            securityDeposit = _executePendingActionOrRevert(previousActionsData);
        }
        if (msg.sender != validator) {
            Utils._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = securityDeposit;
        } else {
            amountToRefund += securityDeposit;
        }
        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee();
    }

    /// @notice See {IUsdnProtocolFallback.getActionablePendingActions}.
    function getActionablePendingActions(address currentUser, uint256 lookAhead, uint256 maxIter)
        external
        view
        returns (Types.PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (actions_, rawIndices_);
        }
        if (maxIter < Constants.MIN_ACTIONABLE_PENDING_ACTIONS_ITER) {
            maxIter = Constants.MIN_ACTIONABLE_PENDING_ACTIONS_ITER;
        }
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }
        actions_ = new Types.PendingAction[](maxIter);
        rawIndices_ = new uint128[](maxIter);

        uint256 lowLatencyDeadline = s._lowLatencyValidatorDeadline;
        // the lookAhead allows to retrieve pending actions which will be actionable some time after block.timestamp. By
        // subtracting this value to `lowLatencyDeadline`, the range where actions are considered actionable with the
        // low-latency oracle is increased
        if (lookAhead > lowLatencyDeadline) {
            lowLatencyDeadline = 0; // avoid underflow
        } else {
            unchecked {
                lowLatencyDeadline -= lookAhead; // checked above
            }
        }
        uint16 middlewareLowLatencyDelay = s._oracleMiddleware.getLowLatencyDelay();
        uint256 onChainDeadline = s._onChainValidatorDeadline;
        // same comment as above, changing this value increases the range where actions are considered actionable
        // with the on-chain oracle
        if (lookAhead > onChainDeadline) {
            onChainDeadline = 0; // avoid underflow
        } else {
            unchecked {
                onChainDeadline -= lookAhead;
            }
        }
        uint256 i;
        uint256 j;
        uint256 arrayLen;
        do {
            // since `i` cannot be greater or equal to `queueLength`, there is no risk of reverting
            (Types.PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.at(i);

            if (candidate.timestamp == 0 || candidate.validator == currentUser) {
                // if the currentUser is equal to the validator of the pending action, then the pending action is not
                // actionable by this user (it will get validated automatically by their action)
                // and so we need to return the next item in the queue so that they can validate a third-party pending
                // action (if any)
                if (arrayLen > 0) {
                    rawIndices_[j] = rawIndex;
                    unchecked {
                        j++;
                    }
                }
                // try the next one
                unchecked {
                    i++;
                }
            } else if (
                _isActionable(candidate.timestamp, lowLatencyDeadline, middlewareLowLatencyDelay, onChainDeadline)
            ) {
                // we found an actionable pending action
                actions_[j] = candidate;
                rawIndices_[j] = rawIndex;

                // continue looking
                unchecked {
                    i++;
                    j++;
                    arrayLen = j;
                }
            } else if (block.timestamp > candidate.timestamp + middlewareLowLatencyDelay) {
                // the pending action is not actionable but some more recent ones might be (with low-latency oracle)
                // continue looking
                if (arrayLen > 0) {
                    rawIndices_[j] = rawIndex;
                    unchecked {
                        j++;
                    }
                }
                unchecked {
                    i++;
                }
            } else {
                // the pending action is not actionable (it is too recent),
                // following actions can't be actionable either so we return
                break;
            }
        } while (i < maxIter);
        assembly ("memory-safe") {
            // shrink the size of the arrays
            mstore(actions_, arrayLen)
            mstore(rawIndices_, arrayLen)
        }
    }

    /// @notice See {IUsdnProtocolVault.usdnPrice(uint128)}.
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(currentPrice, uint128(block.timestamp));
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolVault.usdnPrice(uint128,uint128)}.
    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        Types.Storage storage s = Utils._getMainStorage();

        price_ = _calcUsdnPrice(
            vaultAssetAvailableWithFunding(currentPrice, timestamp),
            currentPrice,
            s._usdn.totalSupply(),
            s._assetDecimals
        );
    }

    /// @notice See {IUsdnProtocolVault.vaultAssetAvailableWithFunding}.
    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (uint256 available_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        (uint256 longAvailable, int256 fee) = Core.longAssetAvailableWithFunding(currentPrice, timestamp);

        return (s._balanceLong + s._balanceVault - FixedPointMathLib.abs(fee)) - longAvailable;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Internal function                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Executes the first actionable pending action.
     * @dev Will revert if the corresponding price data is invalid.
     * @param data The price data and corresponding raw indices.
     * @return securityDepositValue_ The security deposit value of the executed action.
     */
    function _executePendingActionOrRevert(Types.PreviousActionsData calldata data)
        public
        returns (uint256 securityDepositValue_)
    {
        bool success;
        (success,,, securityDepositValue_) = _executePendingAction(data);
        if (!success) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingActionData();
        }
    }

    /**
     * @notice Executes the first actionable pending action and reports the outcome.
     * @param data The price data and corresponding raw indices.
     * @return success_ Whether the price data is valid.
     * @return executed_ Whether the pending action was executed (false if the queue has no actionable item).
     * @return liquidated_ Whether the position corresponding to the pending action was liquidated.
     * @return securityDepositValue_ The security deposit value of the executed action.
     */
    function _executePendingAction(Types.PreviousActionsData calldata data)
        public
        returns (bool success_, bool executed_, bool liquidated_, uint256 securityDepositValue_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = _getActionablePendingAction();
        if (pending.action == Types.ProtocolAction.None) {
            // no pending action
            return (true, false, false, 0);
        }
        uint256 length = data.priceData.length;
        if (data.rawIndices.length != length || length < 1) {
            return (false, false, false, 0);
        }
        uint128 offset;
        unchecked {
            // underflow is desired here (wrap-around)
            offset = rawIndex - data.rawIndices[0];
        }
        if (offset >= length || data.rawIndices[offset] != rawIndex) {
            return (false, false, false, 0);
        }
        bytes calldata priceData = data.priceData[offset];
        // for safety we consider that no pending action was validated by default
        if (pending.action == Types.ProtocolAction.ValidateDeposit) {
            executed_ = _validateDepositWithAction(pending, priceData);
        } else if (pending.action == Types.ProtocolAction.ValidateWithdrawal) {
            executed_ = _validateWithdrawalWithAction(pending, priceData);
        } else if (pending.action == Types.ProtocolAction.ValidateOpenPosition) {
            (executed_, liquidated_,) = ActionsLong._validateOpenPositionWithAction(pending, priceData);
        } else if (pending.action == Types.ProtocolAction.ValidateClosePosition) {
            (executed_, liquidated_) = ActionsLong._validateClosePositionWithAction(pending, priceData);
        }

        success_ = true;

        if (executed_ || liquidated_) {
            Utils._clearPendingAction(pending.validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
            emit IUsdnProtocolEvents.SecurityDepositRefunded(pending.validator, msg.sender, securityDepositValue_);
        }
    }

    /**
     * @notice This is the mutating version of {getActionablePendingActions}, where empty items at the front of the list
     * are removed.
     * @return action_ The first actionable pending action if any, otherwise a struct with all fields set to zero and
     * {IUsdnProtocolTypes.ProtocolAction}'s `None` action.
     * @return rawIndex_ The raw index in the queue for the returned pending action, or zero if empty.
     */
    function _getActionablePendingAction() internal returns (Types.PendingAction memory action_, uint128 rawIndex_) {
        Types.Storage storage s = Utils._getMainStorage();

        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (action_, rawIndex_);
        }
        uint256 maxIter = Constants.MIN_ACTIONABLE_PENDING_ACTIONS_ITER;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint128 lowLatencyDeadline = s._lowLatencyValidatorDeadline;
        uint16 middlewareLowLatencyDelay = s._oracleMiddleware.getLowLatencyDelay();
        uint128 onChainDeadline = s._onChainValidatorDeadline;
        uint256 i;
        uint256 j;
        do {
            // since we will never loop more than `queueLength` times, there is no risk of reverting
            (Types.PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.at(j);
            unchecked {
                i++;
            }
            if (candidate.timestamp == 0) {
                // remove the stale pending action
                s._pendingActionsQueue.clearAt(rawIndex);
                // if we were removing another item than the first one, we increment j (otherwise we keep looking at the
                // first item because it was shifted to the front)
                if (j > 0) {
                    unchecked {
                        j++;
                    }
                }
                // try the next one
                continue;
            } else if (
                _isActionable(candidate.timestamp, lowLatencyDeadline, middlewareLowLatencyDelay, onChainDeadline)
            ) {
                // we found an actionable pending action
                return (candidate, rawIndex);
            } else if (block.timestamp > candidate.timestamp + middlewareLowLatencyDelay) {
                // the pending action is not actionable but some more recent ones might be (with low-latency oracle)
                // continue looking
                unchecked {
                    j++;
                }
                continue;
            }
            // the first pending action is not actionable, none of the following ones will be either
            return (action_, rawIndex_);
        } while (i < maxIter);
    }

    /**
     * @notice Prepares the data for the {initiateDeposit} function.
     * @dev Updates the protocol's balances if the price is fresh.
     * @param validator The address that is supposed to validate the deposit and receive the security deposit.
     * @param amount The amount of asset to deposit.
     * @param sharesOutMin The minimum amount of USDN shares to receive.
     * @param currentPriceData The current price data.
     * @return data_ The transient data for the `deposit` action.
     */
    function _prepareInitiateDepositData(
        address validator,
        uint128 amount,
        uint256 sharesOutMin,
        bytes calldata currentPriceData
    ) internal returns (InitiateDepositData memory data_) {
        Types.Storage storage s = Utils._getMainStorage();

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.InitiateDeposit,
            block.timestamp,
            Utils._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.InitiateDeposit,
            currentPriceData
        );

        if (data_.isLiquidationPending) {
            return data_;
        }

        _checkImbalanceLimitDeposit(amount);

        // apply fees on amount
        data_.feeBps = s._vaultFeeBps;
        uint128 fees = FixedPointMathLib.fullMulDiv(amount, data_.feeBps, Constants.BPS_DIVISOR).toUint128();
        uint128 amountAfterFees = amount - fees;

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.lastPrice = s._lastPrice;
        data_.balanceVault = vaultAssetAvailableWithFunding(data_.lastPrice, uint128(block.timestamp));
        if (data_.balanceVault == 0) {
            // can't mint USDN if the vault is empty
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }

        IUsdn usdn = s._usdn;
        data_.usdnTotalShares = usdn.totalShares();

        // calculate the amount of SDEX tokens to burn
        uint256 usdnSharesToMintEstimated =
            Utils._calcMintUsdnShares(amountAfterFees, data_.balanceVault + fees, data_.usdnTotalShares);
        if (usdnSharesToMintEstimated < sharesOutMin) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountReceivedTooSmall();
        }
        uint256 usdnToMintEstimated = usdn.convertToTokens(usdnSharesToMintEstimated);
        // we want to at least mint 1 wei of USDN
        if (usdnToMintEstimated == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
        }
        uint32 burnRatio = s._sdexBurnOnDepositRatio;
        data_.sdexToBurn = Utils._calcSdexToBurn(usdnToMintEstimated, burnRatio);
    }

    /**
     * @notice Prepares the pending action struct for a deposit and adds it to the queue.
     * @param to The recipient of the minted USDN.
     * @param validator The address that is supposed to validate the deposit and receive the security deposit.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param amount The amount of assets to deposit (before fees).
     * @param data The deposit action data.
     * @return amountToRefund_ The security deposit value of a stale pending action.
     */
    function _createDepositPendingAction(
        address to,
        address validator,
        uint64 securityDepositValue,
        uint128 amount,
        InitiateDepositData memory data
    ) internal returns (uint256 amountToRefund_) {
        Types.DepositPendingAction memory pendingAction = Types.DepositPendingAction({
            action: Types.ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            feeBps: data.feeBps,
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            _unused: 0,
            amount: amount,
            assetPrice: data.lastPrice,
            totalExpo: data.totalExpo,
            balanceVault: data.balanceVault,
            balanceLong: data.balanceLong,
            usdnTotalShares: data.usdnTotalShares
        });

        amountToRefund_ = Core._addPendingAction(validator, Utils._convertDepositPendingAction(pendingAction));
    }

    /**
     * @notice Attempts to initiate a deposit of assets into the vault to mint USDN.
     * @dev Consults the current oracle middleware implementation to know the expected format for the price data, using
     * the {IUsdnProtocolTypes.ProtocolAction}'s `InitiateDeposit` action. The price validation might require payment
     * according to the return value of the {IBaseOracleMiddleware.validationCost} function of the middleware.
     * @param params The parameters for the deposit.
     * @param currentPriceData The current price data.
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action.
     * @return isInitiated_ Whether the action is initiated.
     */
    function _initiateDeposit(InitiateDepositParams memory params, bytes calldata currentPriceData)
        internal
        returns (uint256 amountToRefund_, bool isInitiated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (params.to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (params.validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (params.amount == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }

        InitiateDepositData memory data =
            _prepareInitiateDepositData(params.validator, params.amount, params.sharesOutMin, currentPriceData);

        // early return in case there are still pending liquidations
        if (data.isLiquidationPending) {
            return (params.securityDepositValue, false);
        }

        s._pendingBalanceVault += Utils._toInt256(params.amount);

        amountToRefund_ =
            _createDepositPendingAction(params.to, params.validator, params.securityDepositValue, params.amount, data);

        if (ERC165Checker.supportsInterface(msg.sender, type(IPaymentCallback).interfaceId)) {
            if (data.sdexToBurn > 0) {
                Utils._transferCallback(s._sdex, data.sdexToBurn, address(this));
            }
            Utils._transferCallback(s._asset, params.amount, address(this));
        } else {
            if (data.sdexToBurn > 0) {
                // slither-disable-next-line arbitrary-send-erc20
                address(s._sdex).safeTransferFrom(params.user, address(this), data.sdexToBurn);
            }
            // slither-disable-next-line arbitrary-send-erc20
            address(s._asset).safeTransferFrom(params.user, address(this), params.amount);
        }

        isInitiated_ = true;

        emit IUsdnProtocolEvents.InitiatedDeposit(
            params.to, params.validator, params.amount, data.feeBps, block.timestamp, data.sdexToBurn
        );
    }

    /**
     * @notice Attempts to validate the deposit pending action assigned to the given `validator`.
     * @dev If successful, the pending action will be cleared from the queue.
     * @param validator The address that is supposed to validate the deposit and receive the security deposit.
     * @param priceData The price data for the pending action to validate.
     * @return securityDepositValue_ The value of the security deposit to refund.
     * @return isValidated_ Whether the action is validated.
     */
    function _validateDeposit(address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateDeposit) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        isValidated_ = _validateDepositWithAction(pending, priceData);

        if (isValidated_) {
            Utils._clearPendingAction(validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Attempts to validate the given deposit pending action.
     * @param pending The pending action to validate.
     * @param priceData The corresponding price data.
     * @return isValidated_ Whether the action is validated.
     */
    function _validateDepositWithAction(Types.PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        Types.DepositPendingAction memory deposit = Utils._toDepositPendingAction(pending);

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.ValidateDeposit,
            deposit.timestamp,
            Utils._calcActionId(deposit.validator, deposit.timestamp),
            priceData
        );

        {
            // adjust balances
            (, bool isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
                currentPrice.neutralPrice,
                currentPrice.timestamp,
                s._liquidationIteration,
                Types.ProtocolAction.ValidateDeposit,
                priceData
            );

            // early return in case there are still pending liquidations
            if (isLiquidationPending) {
                return false;
            }
        }

        // we calculate the amount of USDN to mint, either considering the vault balance at the time of the initiate
        // action, or the current balance with the new price. We will use the higher of the two to mint. Funding between
        // the initiate and validate actions is ignored. So any balance difference due to funding will be ignored when
        // calculating the minted USDN
        uint128 fees = FixedPointMathLib.fullMulDiv(deposit.amount, deposit.feeBps, Constants.BPS_DIVISOR).toUint128();
        uint128 amountAfterFees = deposit.amount - fees;

        uint256 balanceVault = deposit.balanceVault;
        if (currentPrice.price < deposit.assetPrice) {
            // without considering the funding, when the price decreases, the balance of the vault increases
            int256 available = Utils._vaultAssetAvailable(
                deposit.totalExpo,
                deposit.balanceVault,
                deposit.balanceLong,
                currentPrice.price.toUint128(),
                deposit.assetPrice
            );
            if (available < 0) {
                // sanity check, should not happen
                balanceVault = 0;
            } else {
                balanceVault = uint256(available);
            }
        }

        s._balanceVault += deposit.amount; // we credit the full deposit amount
        s._pendingBalanceVault -= Utils._toInt256(deposit.amount);

        uint256 mintedTokens = s._usdn.mintShares(
            deposit.to, Utils._calcMintUsdnShares(amountAfterFees, balanceVault + fees, deposit.usdnTotalShares)
        );
        isValidated_ = true;
        emit IUsdnProtocolEvents.ValidatedDeposit(
            deposit.to, deposit.validator, amountAfterFees, mintedTokens, deposit.timestamp
        );
    }

    /**
     * @notice Prepares the data for the {initiateWithdrawal} function.
     * @dev Updates the protocol's balances if the price is fresh.
     * @param validator The address that is supposed to validate the withdrawal and receive the security deposit.
     * @param usdnShares The amount of USDN shares to burn.
     * @param amountOutMin The estimated minimum amount of assets to receive.
     * @param currentPriceData The current price data.
     * @return data_ The transient data for the `withdrawal` action.
     */
    function _prepareWithdrawalData(
        address validator,
        uint152 usdnShares,
        uint256 amountOutMin,
        bytes calldata currentPriceData
    ) internal returns (WithdrawalData memory data_) {
        Types.Storage storage s = Utils._getMainStorage();

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.InitiateWithdrawal,
            block.timestamp,
            Utils._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.InitiateWithdrawal,
            currentPriceData
        );

        // early return in case there are still pending liquidations
        if (data_.isLiquidationPending) {
            return data_;
        }

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.lastPrice = s._lastPrice;
        data_.balanceVault = vaultAssetAvailableWithFunding(data_.lastPrice, uint128(block.timestamp));
        data_.usdnTotalShares = s._usdn.totalShares();
        data_.feeBps = s._vaultFeeBps;
        data_.withdrawalAmountAfterFees =
            Utils._calcAmountToWithdraw(usdnShares, data_.balanceVault, data_.usdnTotalShares, data_.feeBps);
        if (data_.withdrawalAmountAfterFees < amountOutMin) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountReceivedTooSmall();
        }
        _checkImbalanceLimitWithdrawal(data_.withdrawalAmountAfterFees, data_.totalExpo);
    }

    /**
     * @notice Prepares the pending action struct for a withdrawal and adds it to the queue.
     * @param to The recipient of the assets.
     * @param validator The address that is supposed to validate the withdrawal and receive the security deposit.
     * @param usdnShares The amount of USDN shares to burn.
     * @param securityDepositValue The value of the security deposit for the newly created pending action.
     * @param data The withdrawal action data.
     * @return amountToRefund_ Refund The security deposit value of a stale pending action.
     */
    function _createWithdrawalPendingAction(
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        WithdrawalData memory data
    ) internal returns (uint256 amountToRefund_) {
        Types.PendingAction memory action = Utils._convertWithdrawalPendingAction(
            Types.WithdrawalPendingAction({
                action: Types.ProtocolAction.ValidateWithdrawal,
                timestamp: uint40(block.timestamp),
                feeBps: data.feeBps,
                to: to,
                validator: validator,
                securityDepositValue: securityDepositValue,
                sharesLSB: _calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: _calcWithdrawalAmountMSB(usdnShares),
                assetPrice: data.lastPrice,
                totalExpo: data.totalExpo,
                balanceVault: data.balanceVault,
                balanceLong: data.balanceLong,
                usdnTotalShares: data.usdnTotalShares
            })
        );
        amountToRefund_ = Core._addPendingAction(validator, action);
    }

    /**
     * @notice Initiates a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consults the current oracle middleware implementation to know the expected format for the price data, using
     * the {IUsdnProtocolTypes.ProtocolAction}'s `InitiateWithdrawal` action. The price validation might require payment
     * according to the return value of the {IBaseOracleMiddleware.validationCost} function of the middleware.
     * @param params The parameters for the withdrawal.
     * @param currentPriceData The current price data.
     * @return amountToRefund_ If there are pending liquidations we'll refund the sent security deposit,
     * else we'll only refund the security deposit value of the stale pending action.
     * @return isInitiated_ Whether the action is initiated.
     */
    function _initiateWithdrawal(WithdrawalParams memory params, bytes calldata currentPriceData)
        internal
        returns (uint256 amountToRefund_, bool isInitiated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        if (params.to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (params.validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (params.usdnShares == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data =
            _prepareWithdrawalData(params.validator, params.usdnShares, params.amountOutMin, currentPriceData);

        if (data.isLiquidationPending) {
            return (params.securityDepositValue, false);
        }

        amountToRefund_ = _createWithdrawalPendingAction(
            params.to, params.validator, params.usdnShares, params.securityDepositValue, data
        );

        // register the pending withdrawal for imbalance checks of future actions
        s._pendingBalanceVault -= data.withdrawalAmountAfterFees.toInt256();

        IUsdn usdn = s._usdn;
        if (ERC165Checker.supportsInterface(msg.sender, type(IPaymentCallback).interfaceId)) {
            // ask the msg.sender to send USDN shares and check the balance
            Utils._usdnTransferCallback(usdn, params.usdnShares);
        } else {
            // retrieve the USDN shares, check that the balance is sufficient
            usdn.transferSharesFrom(params.user, address(this), params.usdnShares);
        }

        isInitiated_ = true;
        emit IUsdnProtocolEvents.InitiatedWithdrawal(
            params.to, params.validator, usdn.convertToTokens(params.usdnShares), data.feeBps, block.timestamp
        );
    }

    /**
     * @notice Attempts to validate the withdrawal pending action assigned to the given `validator`.
     * @dev If successful, the pending action will be cleared from the queue.
     * @param validator The address that is supposed to validate the withdrawal and receive the security deposit.
     * @param priceData The corresponding price data.
     * @return securityDepositValue_ The value of the security deposit.
     * @return isValidated_ Whether the action is validated.
     */
    function _validateWithdrawal(address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateWithdrawal) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        isValidated_ = _validateWithdrawalWithAction(pending, priceData);

        if (isValidated_) {
            Utils._clearPendingAction(validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Attempts to validate the given withdrawal pending action.
     * @param pending The pending action data.
     * @param priceData The current price data.
     * @return isValidated_ Whether the action is validated.
     */
    function _validateWithdrawalWithAction(Types.PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_)
    {
        Types.Storage storage s = Utils._getMainStorage();

        Types.WithdrawalPendingAction memory withdrawal = Utils._toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            Types.ProtocolAction.ValidateWithdrawal,
            withdrawal.timestamp,
            Utils._calcActionId(withdrawal.validator, withdrawal.timestamp),
            priceData
        );

        (, bool isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            Types.ProtocolAction.ValidateWithdrawal,
            priceData
        );

        // early return in case there are still pending liquidations
        if (isLiquidationPending) {
            return false;
        }

        uint256 available;
        {
            // we calculate the available balance of the vault side at the price of the validate action (ignoring any
            // funding between the initiate and validate)
            int256 vaultAssetAvailable = Utils._vaultAssetAvailable(
                withdrawal.totalExpo,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                currentPrice.price.toUint128(),
                withdrawal.assetPrice
            );

            if (vaultAssetAvailable < 0) {
                vaultAssetAvailable = 0;
            }
            available = uint256(vaultAssetAvailable);

            // we compare it to the available balance from the initiate action
            // we will use the lowest of the two amounts to redeem the underlying asset share
            // cast is safe because vaultAssetAvailable cannot be negative
            if (withdrawal.balanceVault <= uint256(vaultAssetAvailable)) {
                available = withdrawal.balanceVault;
            }
        }

        uint256 shares = Utils._mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);

        // we can add back the _pendingBalanceVault we subtracted in the initiate action
        uint256 tempWithdrawalAfterFees =
            Utils._calcAmountToWithdraw(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares, withdrawal.feeBps);
        s._pendingBalanceVault += tempWithdrawalAfterFees.toInt256();

        IUsdn usdn = s._usdn;
        // calculate the amount of asset to transfer with the same fees as recorded during the initiate action
        uint256 assetToTransferAfterFees =
            Utils._calcAmountToWithdraw(shares, available, withdrawal.usdnTotalShares, withdrawal.feeBps);

        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransferAfterFees > 0) {
            uint256 balanceVault = s._balanceVault;
            // if there aren't enough funds in the vault, send what remains
            if (assetToTransferAfterFees > balanceVault) {
                assetToTransferAfterFees = balanceVault;
            }

            s._balanceVault = balanceVault - assetToTransferAfterFees;
            address(s._asset).safeTransfer(withdrawal.to, assetToTransferAfterFees);
        }

        isValidated_ = true;

        emit IUsdnProtocolEvents.ValidatedWithdrawal(
            withdrawal.to,
            withdrawal.validator,
            assetToTransferAfterFees,
            usdn.convertToTokens(shares),
            withdrawal.timestamp
        );
    }

    /**
     * @notice Checks whether a pending action is actionable, i.e any user can validate it and retrieve the security
     * deposit.
     * @dev Between `initiateTimestamp` and `initiateTimestamp + lowLatencyDeadline`, the validator receives the
     * security deposit.
     * Between `initiateTimestamp + lowLatencyDelay` and `initiateTimestamp + lowLatencyDelay + onChainDeadline`,
     * the validator also receives the security deposit.
     * Outside of those periods, the security deposit goes to the user validating the pending action.
     * @param initiateTimestamp The timestamp at which the action was initiated.
     * @param lowLatencyDeadline The deadline after which the action is actionable with a low latency oracle.
     * @param lowLatencyDelay The amount of time the action can be validated with a low latency oracle.
     * @param onChainDeadline The deadline after which the action is actionable with an on-chain oracle.
     * @return actionable_ Whether the pending action is actionable.
     */
    function _isActionable(
        uint256 initiateTimestamp,
        uint256 lowLatencyDeadline,
        uint256 lowLatencyDelay,
        uint256 onChainDeadline
    ) internal view returns (bool actionable_) {
        if (block.timestamp <= initiateTimestamp + lowLatencyDelay) {
            // the validation must happen with a low-latency oracle
            actionable_ = block.timestamp > initiateTimestamp + lowLatencyDeadline;
        } else {
            // the validation must happen with an on-chain oracle
            actionable_ = block.timestamp > initiateTimestamp + lowLatencyDelay + onChainDeadline;
        }
    }

    /**
     * @notice Checks and reverts if the deposited value breaks the imbalance limits.
     * @param depositValue The deposit value in asset.
     */
    function _checkImbalanceLimitDeposit(uint256 depositValue) internal view {
        Types.Storage storage s = Utils._getMainStorage();

        int256 depositExpoImbalanceLimitBps = s._depositExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (depositExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentLongExpo = (s._totalExpo - s._balanceLong).toInt256();

        // cannot be calculated
        if (currentLongExpo == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo();
        }

        int256 newVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault).safeAdd(int256(depositValue));

        int256 imbalanceBps =
            newVaultExpo.safeSub(currentLongExpo).safeMul(int256(Constants.BPS_DIVISOR)).safeDiv(currentLongExpo);

        if (imbalanceBps > depositExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Checks and reverts if the withdrawn value breaks the imbalance limits.
     * @param withdrawalValue The withdrawal value in asset.
     * @param totalExpo The current total exposure of the long side.
     */
    function _checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) internal view {
        Types.Storage storage s = Utils._getMainStorage();

        int256 withdrawalExpoImbalanceLimitBps = s._withdrawalExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (withdrawalExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newVaultExpo =
            s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault).safeSub(withdrawalValue.toInt256());

        // an imbalance cannot be calculated if the new vault exposure is zero or negative
        if (newVaultExpo <= 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }

        int256 imbalanceBps = (totalExpo - s._balanceLong).toInt256().safeSub(newVaultExpo).safeMul(
            int256(Constants.BPS_DIVISOR)
        ).safeDiv(newVaultExpo);

        if (imbalanceBps > withdrawalExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Calculates the available balance in the vault if the price moves to `currentPrice`.
     * @dev The funding is not taken into account.
     * @param currentPrice The current or predicted price.
     * @return available_ The available balance in the vault.
     */
    function _vaultAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        Types.Storage storage s = Utils._getMainStorage();

        available_ =
            Utils._vaultAssetAvailable(s._totalExpo, s._balanceVault, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Calculates the price of the USDN token as a function of its total supply, the vault balance and the
     * underlying asset price.
     * @param vaultBalance The vault balance.
     * @param assetPrice The price of the asset.
     * @param usdnTotalSupply The total supply of the USDN token.
     * @param assetDecimals The number of decimals of the underlying asset.
     * @return price_ The price of the USDN token.
     */
    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        internal
        pure
        returns (uint256 price_)
    {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** Constants.TOKENS_DECIMALS, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculates the lower 24 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares.
     * @return sharesLSB_ The 24 least significant bits of the USDN shares.
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Calculates the higher 128 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares.
     * @return sharesMSB_ The 128 most significant bits of the USDN shares.
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }
}
