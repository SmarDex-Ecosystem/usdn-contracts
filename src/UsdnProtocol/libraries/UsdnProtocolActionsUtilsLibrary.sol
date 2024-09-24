// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IOwnershipCallback } from "../../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolActionsUtilsLibrary {
    using SafeCast for uint256;
    using SignedMath for int256;

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function liquidate(Types.Storage storage s, bytes calldata currentPriceData, uint16 iterations)
        external
        returns (Types.LiqTickInfo[] memory liquidatedTicks_)
    {
        uint256 balanceBefore = address(this).balance;
        PriceInfo memory currentPrice =
            Utils._getOraclePrice(s, Types.ProtocolAction.Liquidation, 0, "", currentPriceData);

        (liquidatedTicks_,) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            iterations,
            true,
            Types.ProtocolAction.Liquidation,
            currentPriceData
        );

        Utils._refundExcessEther(0, 0, balanceBefore);
        Utils._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateActionablePendingActions(
        Types.Storage storage s,
        Types.PreviousActionsData calldata previousActionsData,
        uint256 maxValidations
    ) external returns (uint256 validatedActions_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (validatedActions_, amountToRefund) = Core._validateMultipleActionable(s, previousActionsData, maxValidations);

        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function transferPositionOwnership(Types.Storage storage s, Types.PositionId calldata posId, address newOwner)
        external
    {
        (bytes32 tickHash, uint256 version) = Utils._tickHash(s, posId.tick);
        if (posId.tickVersion != version) {
            revert IUsdnProtocolErrors.UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        Types.Position storage pos = s._longPositions[tickHash][posId.index];

        if (msg.sender != pos.user) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }
        if (newOwner == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
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
    function getLongPosition(Types.Storage storage s, Types.PositionId memory posId)
        public
        view
        returns (Types.Position memory pos_, uint24 liquidationPenalty_)
    {
        (bytes32 tickHash, uint256 version) = Utils._tickHash(s, posId.tick);
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
     * @param s The storage of the protocol
     * @param params The parameters for the _prepareClosePositionData function
     * @return data_ The close position data
     * @return liquidated_ Whether the position was liquidated and the caller should return early
     */
    function _prepareClosePositionData(
        Types.Storage storage s,
        Types.PrepareInitiateClosePositionParams calldata params
    ) public returns (Types.ClosePositionData memory data_, bool liquidated_) {
        (data_.pos, data_.liquidationPenalty) = getLongPosition(s, params.posId);

        _checkInitiateClosePosition(s, params.owner, params.to, params.validator, params.amountToClose, data_.pos);

        {
            PriceInfo memory currentPrice = Utils._getOraclePrice(
                s,
                Types.ProtocolAction.InitiateClosePosition,
                block.timestamp,
                Utils._calcActionId(params.owner, uint128(block.timestamp)),
                params.currentPriceData
            );
            if (currentPrice.price < params.userMinPrice) {
                revert IUsdnProtocolErrors.UsdnProtocolSlippageMinPriceExceeded();
            }

            (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
                s,
                currentPrice.neutralPrice,
                currentPrice.timestamp,
                s._liquidationIteration,
                false,
                Types.ProtocolAction.InitiateClosePosition,
                params.currentPriceData
            );

            uint256 version = s._tickVersion[params.posId.tick];
            if (version != params.posId.tickVersion) {
                // the current tick version doesn't match the version from the position,
                // that means that the position has been liquidated in this transaction
                return (data_, true);
            }
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * params.amountToClose / data_.pos.amount).toUint128();

        data_.longTradingExpo = s._totalExpo - s._balanceLong;
        data_.liqMulAcc = s._liqMultiplierAccumulator;
        data_.lastPrice = s._lastPrice;

        // the approximate value position to remove is calculated with `_lastPrice`, so not taking into account
        // any fees. This way, the removal of the position doesn't affect the liquidation multiplier calculations

        // to have maximum precision, we do not pre-compute the liquidation multiplier with a fixed
        // precision just now, we will store it in the pending action later, to be used in the validate action
        int24 tick = Utils.calcTickWithoutPenalty(params.posId.tick, data_.liquidationPenalty);
        uint128 liqPriceWithoutPenalty =
            Utils.getEffectivePriceForTick(tick, data_.lastPrice, data_.longTradingExpo, data_.liqMulAcc);

        uint256 balanceLong = s._balanceLong;

        data_.tempPositionValue =
            _assetToRemove(balanceLong, data_.lastPrice, liqPriceWithoutPenalty, data_.totalExpoToClose);

        uint128 priceAfterFees =
            (data_.lastPrice - data_.lastPrice * s._positionFeeBps / Constants.BPS_DIVISOR).toUint128();

        uint256 posValueAfterFees =
            _assetToRemove(balanceLong, priceAfterFees, liqPriceWithoutPenalty, data_.totalExpoToClose);

        // we perform the imbalance check with the position value after fees
        // the position value after fees is smaller than the position value before fees so the subtraction is safe
        _checkImbalanceLimitClose(
            s, data_.totalExpoToClose, posValueAfterFees, data_.tempPositionValue - posValueAfterFees
        );
    }

    /**
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on the vault side, otherwise revert
     * @param s The storage of the protocol
     * @param posTotalExpoToClose The total expo to remove position
     * @param posValueToCloseAfterFees The value to remove from the position after the fees are applied
     * @param fees The fees applied to the position, going to the vault
     */
    function _checkImbalanceLimitClose(
        Types.Storage storage s,
        uint256 posTotalExpoToClose,
        uint256 posValueToCloseAfterFees,
        uint256 fees
    ) internal view {
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

        int256 newLongBalance = s._balanceLong.toInt256().safeSub(posValueToCloseAfterFees.toInt256());
        uint256 newTotalExpo = s._totalExpo - posTotalExpoToClose;
        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault + fees.toInt256());

        int256 imbalanceBps = Utils._calcImbalanceCloseBps(currentVaultExpo, newLongBalance, newTotalExpo);

        if (imbalanceBps > closeExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Perform checks for the initiate close position action
     * @dev Reverts if the to address is zero, the position was not validated yet, the position is not owned by the
     * user, the amount to close is higher than the position amount, or the amount to close is zero
     * @param s The storage of the protocol
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address of the validator
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param pos The position to close
     */
    function _checkInitiateClosePosition(
        Types.Storage storage s,
        address owner,
        address to,
        address validator,
        uint128 amountToClose,
        Types.Position memory pos
    ) internal view {
        if (to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (pos.user != owner) {
            revert IUsdnProtocolErrors.UsdnProtocolUnauthorized();
        }
        if (!pos.validated) {
            revert IUsdnProtocolErrors.UsdnProtocolPositionNotValidated();
        }
        if (amountToClose == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }
        if (amountToClose > pos.amount) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        // make sure the remaining position is higher than _minLongPosition
        // for the Rebalancer, we allow users to close their position fully in every case
        uint128 remainingAmount = pos.amount - amountToClose;
        if (remainingAmount > 0 && remainingAmount < s._minLongPosition) {
            IBaseRebalancer rebalancer = s._rebalancer;
            if (owner == address(rebalancer)) {
                // note: the rebalancer always indicates the rebalancer user's address as validator
                uint128 userPosAmount = rebalancer.getUserDepositData(validator).amount;
                if (amountToClose != userPosAmount) {
                    revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
                }
            } else {
                revert IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall();
            }
        }
    }

    /**
     * @notice Calculate how much assets must be removed from the long balance due to a position closing
     * @dev The amount is bound by the amount of assets available on the long side
     * @param balanceLong The balance of long positions (with asset decimals)
     * @param price The price to use for the position value calculation
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo of the position
     * @return boundedPosValue_ The amount of assets to remove from the long balance, bound by zero and the available
     * long balance
     */
    function _assetToRemove(uint256 balanceLong, uint128 price, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        internal
        pure
        returns (uint256 boundedPosValue_)
    {
        // calculate position value
        int256 positionValue = Utils._positionValue(price, liqPriceWithoutPenalty, posExpo);

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
}
