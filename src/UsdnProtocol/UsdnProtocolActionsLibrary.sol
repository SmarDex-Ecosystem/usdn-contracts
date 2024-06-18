// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";

import { PriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolActions } from "../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import {
    DepositPendingAction,
    LiquidationsEffects,
    LongPendingAction,
    PendingAction,
    Position,
    PositionId,
    PreviousActionsData,
    ProtocolAction,
    TickData,
    WithdrawalPendingAction
} from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../libraries/HugeUint.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { Permit2TokenBitfield } from "../libraries/Permit2TokenBitfield.sol";
import { IOwnershipCallback } from "../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { Storage, CachedProtocolState } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "./UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as longLib, LiquidationData } from "./UsdnProtocolLongLibrary.sol";

struct InitiateClosePositionParams {
    PositionId posId;
    uint128 amountToClose;
    address to;
    address payable validator;
}

/**
 * @notice Parameters for the internal `_initiateOpenPosition` function
 * @param user The address of the user initiating the open position
 * @param to The address that will be the owner of the position
 * @param validator The address that will validate the open position
 * @param amount The amount of wstETH to deposit
 * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
 * @param securityDepositValue The value of the security deposit for the newly created pending action
 * @param permit2TokenBitfield The permit2 bitfield
 * @param currentPriceData The current price data (used to calculate the temporary leverage and entry price,
 * pending validation)
 */
struct InitiateOpenPositionParams {
    address user;
    address to;
    address validator;
    uint128 amount;
    uint128 desiredLiqPrice;
    uint64 securityDepositValue;
    Permit2TokenBitfield.Bitfield permit2TokenBitfield;
}

library UsdnProtocolActionsLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;

    /**
     * @dev Structure to hold the transient data during `_initiateDeposit`
     * @param pendingActionPrice The adjusted price with position fees applied
     * @param isLiquidationPending Whether some liquidations still need to be performed
     * @param totalExpo The total expo of the long side
     * @param balanceLong The long side balance
     * @param balanceVault The vault side balance, calculated according to the pendingActionPrice
     * @param usdnTotalShares Total minted shares of USDN
     * @param sdexToBurn The amount of SDEX to burn for the deposit
     */
    struct InitiateDepositData {
        uint128 pendingActionPrice;
        bool isLiquidationPending;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 usdnTotalShares;
        uint256 sdexToBurn;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateWithdrawal`
     * @param pendingActionPrice The adjusted price with position fees applied
     * @param usdnTotalShares The total shares supply of USDN
     * @param totalExpo The current total expo
     * @param balanceLong The current long balance
     * @param balanceVault The vault balance, adjusted according to the pendingActionPrice
     * @param withdrawalAmount The predicted amount of assets that will be withdrawn
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct WithdrawalData {
        uint128 pendingActionPrice;
        uint256 usdnTotalShares;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 withdrawalAmount;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateOpenPosition`
     * @param adjustedPrice The adjusted price with position fees applied
     * @param posId The new position id
     * @param liquidationPenalty The liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct InitiateOpenPositionData {
        uint128 adjustedPrice;
        PositionId posId;
        uint8 liquidationPenalty;
        uint128 positionTotalExpo;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during `_validateOpenPosition`
     * @param action The long pending action
     * @param startPrice The new entry price of the position
     * @param tickHash The tick hash
     * @param pos The position object
     * @param liqPriceWithoutPenalty The new liquidation price without penalty
     * @param leverage The new leverage
     * @param liquidationPenalty The liquidation penalty for the position's tick
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct ValidateOpenPositionData {
        LongPendingAction action;
        uint128 startPrice;
        bytes32 tickHash;
        Position pos;
        uint128 liqPriceWithoutPenalty;
        uint128 leverage;
        uint8 liquidationPenalty;
        bool isLiquidationPending;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateClosePosition`
     * @param pos The position to close
     * @param liquidationPenalty The liquidation penalty
     * @param totalExpoToClose The total expo to close
     * @param lastPrice The price after the last balances update
     * @param tempPositionValue The bounded value of the position that was removed from the long balance
     * @param longTradingExpo The long trading expo
     * @param liqMulAcc The liquidation multiplier accumulator
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct ClosePositionData {
        Position pos;
        uint8 liquidationPenalty;
        uint128 totalExpoToClose;
        uint128 lastPrice;
        uint256 tempPositionValue;
        uint256 longTradingExpo;
        HugeUint.Uint512 liqMulAcc;
        bool isLiquidationPending;
    }

    // / @inheritdoc IUsdnProtocolActions
    function initiateDeposit(
        Storage storage s,
        uint128 amount,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            // revert UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _initiateDeposit(
            s, msg.sender, to, validator, amount, securityDepositValue, permit2TokenBitfield, currentPriceData
        );

        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function validateDeposit(
        Storage storage s,
        address payable validator,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _validateDeposit(s, validator, depositPriceData);
        if (msg.sender != validator) {
            _refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function initiateWithdrawal(
        Storage storage s,
        uint152 usdnShares,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            // revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) =
            _initiateWithdrawal(s, msg.sender, to, validator, usdnShares, securityDepositValue, currentPriceData);

        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function validateWithdrawal(
        Storage storage s,
        address payable validator,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _validateWithdrawal(s, validator, withdrawalPriceData);
        if (msg.sender != validator) {
            _refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function initiateOpenPosition(
        Storage storage s,
        InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_, PositionId memory posId_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            // revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;
        params.securityDepositValue = securityDepositValue;
        uint256 amountToRefund;
        (posId_, amountToRefund, success_) = _initiateOpenPosition(s, params, currentPriceData);

        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function validateOpenPosition(
        Storage storage s,
        address payable validator,
        bytes calldata openPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liquidated;
        (amountToRefund, success_, liquidated) = _validateOpenPosition(s, validator, openPriceData);
        if (msg.sender != validator) {
            _refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_ || liquidated) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function initiateClosePosition(
        Storage storage s,
        InitiateClosePositionParams memory params,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            // revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liq;
        (amountToRefund, success_, liq) = _initiateClosePosition(
            s,
            msg.sender,
            params.to,
            params.validator,
            params.posId,
            params.amountToClose,
            securityDepositValue,
            currentPriceData
        );

        if (success_ || liq) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function validateClosePosition(
        Storage storage s,
        address payable validator,
        bytes calldata closePriceData,
        PreviousActionsData calldata previousActionsData
    ) external returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        bool liq;
        (amountToRefund, success_, liq) = _validateClosePosition(s, validator, closePriceData);
        if (msg.sender != validator) {
            _refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_ || liq) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function liquidate(Storage storage s, bytes calldata currentPriceData, uint16 iterations)
        external
        returns (uint256 liquidatedPositions_)
    {
        uint256 balanceBefore = address(this).balance;
        PriceInfo memory currentPrice = _getOraclePrice(s, ProtocolAction.Liquidation, 0, "", currentPriceData);

        (liquidatedPositions_,) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            iterations,
            true,
            ProtocolAction.Liquidation,
            currentPriceData
        );

        _refundExcessEther(0, 0, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function validateActionablePendingActions(
        Storage storage s,
        PreviousActionsData calldata previousActionsData,
        uint256 maxValidations
    ) external returns (uint256 validatedActions_) {
        uint256 balanceBefore = address(this).balance;
        uint256 amountToRefund;

        if (maxValidations > previousActionsData.rawIndices.length) {
            maxValidations = previousActionsData.rawIndices.length;
        }
        do {
            (, bool executed, bool liq, uint256 securityDepositValue) = _executePendingAction(s, previousActionsData);
            if (!executed && !liq) {
                break;
            }
            unchecked {
                validatedActions_++;
                amountToRefund += securityDepositValue;
            }
        } while (validatedActions_ < maxValidations);
        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee(s);
    }

    // / @inheritdoc IUsdnProtocolActions
    function transferPositionOwnership(Storage storage s, PositionId calldata posId, address newOwner) external {
        (bytes32 tickHash, uint256 version) = vaultLib._tickHash(s, posId.tick);
        if (posId.tickVersion != version) {
            // revert UsdnProtocolOutdatedTick(version, posId.tickVersion);
        }
        Position storage pos = s._longPositions[tickHash][posId.index];

        if (msg.sender != pos.user) {
            // revert UsdnProtocolUnauthorized();
        }
        if (newOwner == address(0)) {
            // revert UsdnProtocolInvalidAddressTo();
        }

        pos.user = newOwner;

        if (ERC165Checker.supportsInterface(newOwner, type(IOwnershipCallback).interfaceId)) {
            IOwnershipCallback(newOwner).ownershipCallback(msg.sender, posId);
        }

        // emit PositionOwnershipTransferred(posId, msg.sender, newOwner);
    }

    /**
     * @notice Calculate the profits and losses of the long side, calculate the funding and apply protocol fees,
     * calculate the new liquidation multiplier and the temporary new balances for each side
     * @dev This function updates the state of `_lastPrice`, `_lastUpdateTimestamp`, `_lastFunding`, but does not
     * update the balances. This is left to the caller
     * @param currentPrice The current price
     * @param timestamp The timestamp of the current price
     * @return isPriceRecent_ Whether the price was updated or was already the most recent price
     * @return tempLongBalance_ The new balance of the long side, could be negative (temporarily)
     * @return tempVaultBalance_ The new balance of the vault side, could be negative (temporarily)
     */
    function _applyPnlAndFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        internal
        returns (bool isPriceRecent_, int256 tempLongBalance_, int256 tempVaultBalance_)
    {
        // cache variable for optimization
        uint128 lastUpdateTimestamp = s._lastUpdateTimestamp;
        // if the price is not fresh, do nothing
        if (timestamp <= lastUpdateTimestamp) {
            return (timestamp == lastUpdateTimestamp, s._balanceLong.toInt256(), s._balanceVault.toInt256());
        }

        // update the funding EMA
        int256 ema = coreLib._updateEMA(s, timestamp - lastUpdateTimestamp);

        // calculate the funding
        (int256 fundAsset, int256 fund) = coreLib._fundingAsset(s, timestamp, ema);

        // take protocol fee on the funding value
        (int256 fee, int256 fundWithFee, int256 fundAssetWithFee) = coreLib._calculateFee(s, fund, fundAsset);

        // we subtract the fee from the total balance
        int256 totalBalance = s._balanceLong.toInt256().safeAdd(s._balanceVault.toInt256()).safeSub(fee);
        // calculate new balances (for now, any bad debt has not been repaid, balances could become negative)

        if (fund > 0) {
            // in case of positive funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the vault balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = coreLib._longAssetAvailable(s, currentPrice).safeSub(fundAsset);
        } else {
            // in case of negative funding, the vault balance must be decremented by the totality of the funding amount
            // however, since we deducted the fee amount from the total balance, the long balance will be incremented
            // only by the funding amount minus the fee amount
            tempLongBalance_ = coreLib._longAssetAvailable(s, currentPrice).safeSub(fundAssetWithFee);
        }
        tempVaultBalance_ = totalBalance.safeSub(tempLongBalance_);

        // update state variables
        s._lastPrice = currentPrice;
        s._lastUpdateTimestamp = timestamp;
        s._lastFunding = fundWithFee;

        isPriceRecent_ = true;
    }

    /**
     * @notice The deposit vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the deposit limit on the vault side, otherwise revert
     * @param depositValue The deposit value in asset
     */
    function _checkImbalanceLimitDeposit(Storage storage s, uint256 depositValue) internal view {
        int256 depositExpoImbalanceLimitBps = s._depositExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (depositExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentLongExpo = (s._totalExpo - s._balanceLong).toInt256();

        // cannot be calculated
        if (currentLongExpo == 0) {
            // revert UsdnProtocolInvalidLongExpo();
        }

        int256 newVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault).safeAdd(int256(depositValue));

        int256 imbalanceBps =
            newVaultExpo.safeSub(currentLongExpo).safeMul(int256(s.BPS_DIVISOR)).safeDiv(currentLongExpo);

        if (imbalanceBps >= depositExpoImbalanceLimitBps) {
            // revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The withdrawal imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the withdrawal limit on the long side, otherwise revert
     * @param withdrawalValue The withdrawal value in asset
     * @param totalExpo The current total expo
     */
    function _checkImbalanceLimitWithdrawal(Storage storage s, uint256 withdrawalValue, uint256 totalExpo)
        internal
        view
    {
        int256 withdrawalExpoImbalanceLimitBps = s._withdrawalExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (withdrawalExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newVaultExpo =
            s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault).safeSub(withdrawalValue.toInt256());

        // cannot be calculated if equal to zero
        if (newVaultExpo == 0) {
            // revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = (totalExpo - s._balanceLong).toInt256().safeSub(newVaultExpo).safeMul(
            int256(s.BPS_DIVISOR)
        ).safeDiv(newVaultExpo);

        if (imbalanceBps >= withdrawalExpoImbalanceLimitBps) {
            // revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The open long imbalance limit state verification. Revert
     * @dev To ensure that the protocol does not imbalance more than
     * the open limit on the long side, otherwise revert
     * @param openTotalExpoValue The open position expo value
     * @param openCollatValue The open position collateral value
     */
    function _checkImbalanceLimitOpen(Storage storage s, uint256 openTotalExpoValue, uint256 openCollatValue)
        internal
        view
    {
        int256 openExpoImbalanceLimitBps = s._openExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (openExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault);
        int256 imbalanceBps = longLib._calcImbalanceOpenBps(
            s, currentVaultExpo, (s._balanceLong + openCollatValue).toInt256(), s._totalExpo + openTotalExpoValue
        );

        if (imbalanceBps >= openExpoImbalanceLimitBps) {
            // revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice The close vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the close limit on the vault side, otherwise revert
     * @param posTotalExpoToClose The total expo to remove position
     * @param posValueToClose The value to remove from the position
     */
    function _checkImbalanceLimitClose(Storage storage s, uint256 posTotalExpoToClose, uint256 posValueToClose)
        internal
        view
    {
        int256 closeExpoImbalanceLimitBps = s._closeExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (closeExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newLongBalance = s._balanceLong.toInt256().safeSub(posValueToClose.toInt256());
        uint256 newTotalExpo = s._totalExpo - posTotalExpoToClose;
        int256 currentVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault);

        int256 imbalanceBps = longLib._calcImbalanceCloseBps(s, currentVaultExpo, newLongBalance, newTotalExpo);

        if (imbalanceBps >= closeExpoImbalanceLimitBps) {
            // revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Send rewards to the liquidator
     * @dev Should still emit an event if liquidationRewards = 0 to better keep track of those anomalies as rewards for
     * those will be managed off-chain
     * @param liquidatedTicks The number of ticks that were liquidated
     * @param remainingCollateral The amount of collateral remaining after liquidations
     * @param rebased Whether a USDN rebase was performed
     * @param action The protocol action that triggered liquidations
     * @param rebaseCallbackResult The rebase callback result, if any
     * @param priceData The price oracle update data
     */
    function _sendRewardsToLiquidator(
        Storage storage s,
        uint16 liquidatedTicks,
        int256 remainingCollateral,
        bool rebased,
        ProtocolAction action,
        bytes memory rebaseCallbackResult,
        bytes memory priceData
    ) internal {
        // get how much we should give to the liquidator as rewards
        uint256 liquidationRewards = s._liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, remainingCollateral, rebased, action, rebaseCallbackResult, priceData
        );

        // avoid underflows in the situation of extreme bad debt
        if (s._balanceVault < liquidationRewards) {
            liquidationRewards = s._balanceVault;
        }

        // update the vault's balance
        unchecked {
            s._balanceVault -= liquidationRewards;
        }

        // transfer rewards (assets) to the liquidator
        address(s._asset).safeTransfer(msg.sender, liquidationRewards);

        // emit LiquidatorRewarded(msg.sender, liquidationRewards);
    }

    /**
     * @notice Prepare the data for the `initiateDeposit` function
     * @param validator The validator address
     * @param amount The amount of asset to deposit
     * @param currentPriceData The price data for the initiate action
     * @return data_ The transient data for the `deposit` action
     */
    function _prepareInitiateDepositData(
        Storage storage s,
        address validator,
        uint128 amount,
        bytes calldata currentPriceData
    ) internal returns (InitiateDepositData memory data_) {
        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.InitiateDeposit,
            block.timestamp,
            _calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.InitiateDeposit,
            currentPriceData
        );

        if (data_.isLiquidationPending) {
            return data_;
        }

        _checkImbalanceLimitDeposit(s, amount);

        // apply fees on price
        data_.pendingActionPrice =
            (currentPrice.price - currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.balanceVault = vaultLib._vaultAssetAvailable(
            data_.totalExpo, s._balanceVault, data_.balanceLong, data_.pendingActionPrice, s._lastPrice
        ).toUint256();
        data_.usdnTotalShares = s._usdn.totalShares();

        // calculate the amount of SDEX tokens to burn
        uint256 usdnSharesToMintEstimated =
            vaultLib._calcMintUsdnShares(s, amount, data_.balanceVault, data_.usdnTotalShares, data_.pendingActionPrice);
        uint256 usdnToMintEstimated = s._usdn.convertToTokens(usdnSharesToMintEstimated);
        // we want to at least mint 1 wei of USDN
        if (usdnToMintEstimated == 0) {
            // revert UsdnProtocolDepositTooSmall();
        }
        uint32 burnRatio = s._sdexBurnOnDepositRatio;
        data_.sdexToBurn = vaultLib._calcSdexToBurn(s, usdnToMintEstimated, burnRatio);
        // we want to at least burn 1 wei of SDEX if SDEX burning is enabled
        if (burnRatio != 0 && data_.sdexToBurn == 0) {
            // revert UsdnProtocolDepositTooSmall();
        }
    }

    /**
     * @notice Prepare the pending action struct for a deposit and add it to the queue
     * @param to The address that will receive the minted USDN
     * @param validator The address that will validate the deposit
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param amount The amount of assets to deposit
     * @param data The deposit action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createDepositPendingAction(
        Storage storage s,
        address to,
        address validator,
        uint64 securityDepositValue,
        uint128 amount,
        InitiateDepositData memory data
    ) internal returns (uint256 amountToRefund_) {
        DepositPendingAction memory pendingAction = DepositPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            _unused: 0,
            amount: amount,
            assetPrice: data.pendingActionPrice,
            totalExpo: data.totalExpo,
            balanceVault: data.balanceVault,
            balanceLong: data.balanceLong,
            usdnTotalShares: data.usdnTotalShares
        });

        amountToRefund_ = coreLib._addPendingAction(s, validator, coreLib._convertDepositPendingAction(pendingAction));
    }

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * @param user The address of the user initiating the deposit
     * @param to The address to receive the USDN tokens
     * @param validator The address that will validate the deposit
     * @param amount The amount of wstETH to deposit
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param permit2TokenBitfield The permit2 bitfield
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     */
    function _initiateDeposit(
        Storage storage s,
        address user,
        address to,
        address validator,
        uint128 amount,
        uint64 securityDepositValue,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData
    ) internal returns (uint256 amountToRefund_, bool isInitiated_) {
        if (to == address(0)) {
            // revert UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            // revert UsdnProtocolInvalidAddressValidator();
        }
        if (amount == 0) {
            // revert UsdnProtocolZeroAmount();
        }

        InitiateDepositData memory data = _prepareInitiateDepositData(s, validator, amount, currentPriceData);

        // early return in case there are still pending liquidations
        if (data.isLiquidationPending) {
            return (securityDepositValue, false);
        }

        amountToRefund_ = _createDepositPendingAction(s, to, validator, securityDepositValue, amount, data);

        if (data.sdexToBurn > 0) {
            // send SDEX to the dead address
            if (permit2TokenBitfield.useForSdex()) {
                address(s._sdex).permit2TransferFrom(user, s.DEAD_ADDRESS, data.sdexToBurn);
            } else {
                address(s._sdex).safeTransferFrom(user, s.DEAD_ADDRESS, data.sdexToBurn);
            }
        }

        // transfer assets
        if (permit2TokenBitfield.useForAsset()) {
            address(s._asset).permit2TransferFrom(user, address(this), amount);
        } else {
            address(s._asset).safeTransferFrom(user, address(this), amount);
        }
        s._pendingBalanceVault += coreLib._toInt256(amount);

        isInitiated_ = true;

        // emit InitiatedDeposit(to, validator, amount, block.timestamp);
    }

    /**
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     */
    function _validateDeposit(Storage storage s, address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != ProtocolAction.ValidateDeposit) {
            // revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            // revert UsdnProtocolInvalidPendingAction();
        }

        isValidated_ = _validateDepositWithAction(s, pending, priceData);

        if (isValidated_) {
            coreLib._clearPendingAction(s, validator, rawIndex);
            return (pending.securityDepositValue, true);
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the `deposit` action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     */
    function _validateDepositWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_)
    {
        DepositPendingAction memory deposit = coreLib._toDepositPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.ValidateDeposit,
            deposit.timestamp,
            _calcActionId(deposit.validator, deposit.timestamp),
            priceData
        );

        // adjust balances
        (, bool isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.ValidateDeposit,
            priceData
        );

        // early return in case there are still pending liquidations
        if (isLiquidationPending) {
            return false;
        }

        // we calculate the amount of USDN to mint, either considering the asset price at the time of the initiate
        // action, or the current price provided for validation. We will use the lower of the two amounts to mint
        // apply fees on price
        uint128 priceWithFees = (currentPrice.price - currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        uint256 usdnSharesToMint1 = vaultLib._calcMintUsdnShares(
            s, deposit.amount, deposit.balanceVault, deposit.usdnTotalShares, deposit.assetPrice
        );

        uint256 usdnSharesToMint2 = vaultLib._calcMintUsdnShares(
            s,
            deposit.amount,
            // calculate the available balance in the vault side if the price moves to `priceWithFees`
            vaultLib._vaultAssetAvailable(
                deposit.totalExpo, deposit.balanceVault, deposit.balanceLong, priceWithFees, deposit.assetPrice
            ).toUint256(),
            deposit.usdnTotalShares,
            priceWithFees
        );

        uint256 usdnSharesToMint;
        // we use the lower of the two amounts to mint
        if (usdnSharesToMint1 <= usdnSharesToMint2) {
            usdnSharesToMint = usdnSharesToMint1;
        } else {
            usdnSharesToMint = usdnSharesToMint2;
        }

        s._balanceVault += deposit.amount;
        s._pendingBalanceVault -= coreLib._toInt256(deposit.amount);

        uint256 mintedTokens = s._usdn.mintShares(deposit.to, usdnSharesToMint);
        isValidated_ = true;
        // emit ValidatedDeposit(deposit.to, deposit.validator, deposit.amount, mintedTokens, deposit.timestamp);
    }

    /**
     * @notice Update protocol balances, then prepare the data for the withdrawal action
     * @dev Reverts if the imbalance limit is reached
     * @param validator The validator address
     * @param usdnShares The amount of USDN shares to burn
     * @param currentPriceData The current price data
     * @return data_ The withdrawal data struct
     */
    function _prepareWithdrawalData(
        Storage storage s,
        address validator,
        uint152 usdnShares,
        bytes calldata currentPriceData
    ) internal returns (WithdrawalData memory data_) {
        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.InitiateWithdrawal,
            block.timestamp,
            _calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.InitiateWithdrawal,
            currentPriceData
        );

        // early return in case there are still pending liquidations
        if (data_.isLiquidationPending) {
            return data_;
        }

        // apply fees on price
        data_.pendingActionPrice =
            (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.balanceVault = vaultLib._vaultAssetAvailable(
            data_.totalExpo, s._balanceVault, data_.balanceLong, data_.pendingActionPrice, s._lastPrice
        ).toUint256();
        data_.usdnTotalShares = s._usdn.totalShares();
        data_.withdrawalAmount = vaultLib._calcBurnUsdn(usdnShares, data_.balanceVault, data_.usdnTotalShares);

        _checkImbalanceLimitWithdrawal(s, data_.withdrawalAmount, data_.totalExpo);
    }

    /**
     * @notice Prepare the pending action struct for a withdrawal and add it to the queue
     * @param to The address that will receive the assets
     * @param validator The address that will validate the withdrawal
     * @param usdnShares The amount of USDN shares to burn
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The withdrawal action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createWithdrawalPendingAction(
        Storage storage s,
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        WithdrawalData memory data
    ) internal returns (uint256 amountToRefund_) {
        PendingAction memory action = coreLib._convertWithdrawalPendingAction(
            WithdrawalPendingAction({
                action: ProtocolAction.ValidateWithdrawal,
                timestamp: uint40(block.timestamp),
                to: to,
                validator: validator,
                securityDepositValue: securityDepositValue,
                sharesLSB: vaultLib._calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: vaultLib._calcWithdrawalAmountMSB(usdnShares),
                assetPrice: data.pendingActionPrice,
                totalExpo: data.totalExpo,
                balanceVault: data.balanceVault,
                balanceLong: data.balanceLong,
                usdnTotalShares: data.usdnTotalShares
            })
        );
        amountToRefund_ = coreLib._addPendingAction(s, validator, action);
    }

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * @param user The address of the user initiating the withdrawal
     * @param to The address that will receive the assets
     * @param validator The address that will validate the withdrawal
     * @param usdnShares The amount of USDN shares to burn
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     */
    function _initiateWithdrawal(
        Storage storage s,
        address user,
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) internal returns (uint256 amountToRefund_, bool isInitiated_) {
        if (to == address(0)) {
            // revert UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            // revert UsdnProtocolInvalidAddressValidator();
        }
        if (usdnShares == 0) {
            // revert UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data = _prepareWithdrawalData(s, validator, usdnShares, currentPriceData);

        if (data.isLiquidationPending) {
            return (securityDepositValue, false);
        }

        amountToRefund_ = _createWithdrawalPendingAction(s, to, validator, usdnShares, securityDepositValue, data);

        // retrieve the USDN tokens, check that the balance is sufficient
        s._usdn.transferSharesFrom(user, address(this), usdnShares);
        s._pendingBalanceVault -= data.withdrawalAmount.toInt256();

        isInitiated_ = true;
        // emit InitiatedWithdrawal(to, validator, s._usdn.convertToTokens(usdnShares), block.timestamp);
    }

    /**
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     */
    function _validateWithdrawal(Storage storage s, address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != ProtocolAction.ValidateWithdrawal) {
            // revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            // revert UsdnProtocolInvalidPendingAction();
        }

        isValidated_ = _validateWithdrawalWithAction(s, pending, priceData);

        if (isValidated_) {
            coreLib._clearPendingAction(s, validator, rawIndex);
            return (pending.securityDepositValue, true);
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the `withdrawal` action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     */
    function _validateWithdrawalWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_)
    {
        WithdrawalPendingAction memory withdrawal = coreLib._toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.ValidateWithdrawal,
            withdrawal.timestamp,
            _calcActionId(withdrawal.validator, withdrawal.timestamp),
            priceData
        );

        (, bool isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.ValidateWithdrawal,
            priceData
        );

        // early return in case there are still pending liquidations
        if (isLiquidationPending) {
            return false;
        }

        // apply fees on price
        uint128 withdrawalPriceWithFees =
            (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        // we calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share
        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = vaultLib._vaultAssetAvailable(
            withdrawal.totalExpo,
            withdrawal.balanceVault,
            withdrawal.balanceLong,
            withdrawalPriceWithFees,
            withdrawal.assetPrice
        ).toUint256();
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        uint256 shares = coreLib._mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);

        // we can add back the _pendingBalanceVault we subtracted in the initiate action
        uint256 tempWithdrawal = vaultLib._calcBurnUsdn(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares);
        s._pendingBalanceVault += tempWithdrawal.toInt256();

        uint256 assetToTransfer = vaultLib._calcBurnUsdn(shares, available, s._usdn.totalShares());

        s._usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransfer > 0) {
            s._balanceVault -= assetToTransfer;
            address(s._asset).safeTransfer(withdrawal.to, assetToTransfer);
        }

        isValidated_ = true;

        // emit ValidatedWithdrawal(
        //     withdrawal.to, withdrawal.validator, assetToTransfer, s._usdn.convertToTokens(shares),
        // withdrawal.timestamp
        // );
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate open position action
     * @dev Reverts if the imbalance limit is reached, or if the safety margin is not respected
     * @param validator The address of the validator
     * @param amount The amount of wstETH to deposit
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty
     * @param currentPriceData The current price data
     * @return data_ The temporary data for the open position action
     */
    function _prepareInitiateOpenPositionData(
        Storage storage s,
        address validator,
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) internal returns (InitiateOpenPositionData memory data_) {
        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.InitiateOpenPosition,
            block.timestamp,
            _calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );
        data_.adjustedPrice = (currentPrice.price + currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        uint128 neutralPrice = currentPrice.neutralPrice.toUint128();

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.InitiateOpenPosition,
            currentPriceData
        );

        // early return in case there are still pending liquidations
        if (data_.isLiquidationPending) {
            return data_;
        }

        // we calculate the closest valid tick down for the desired liq price with liquidation penalty
        data_.posId.tick = longLib.getEffectiveTickForPrice(s, desiredLiqPrice);
        data_.liquidationPenalty = longLib.getTickLiquidationPenalty(s, data_.posId.tick);

        // calculate effective liquidation price
        uint128 liqPrice = longLib.getEffectivePriceForTick(s, data_.posId.tick);

        // liquidation price must be at least x% below the current price
        longLib._checkSafetyMargin(s, neutralPrice, liqPrice);

        // remove liquidation penalty for leverage and total expo calculations
        uint128 liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
            s, longLib._calcTickWithoutPenalty(s, data_.posId.tick, data_.liquidationPenalty)
        );
        _checkOpenPositionLeverage(s, data_.adjustedPrice, liqPriceWithoutPenalty);

        data_.positionTotalExpo = longLib._calcPositionTotalExpo(amount, data_.adjustedPrice, liqPriceWithoutPenalty);
        _checkImbalanceLimitOpen(s, data_.positionTotalExpo, amount);
    }

    /**
     * @notice Prepare the pending action struct for an open position and add it to the queue
     * @param to The address that will be the owner of the position
     * @param validator The address that will validate the open position
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The open position action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createOpenPendingAction(
        Storage storage s,
        address to,
        address validator,
        uint64 securityDepositValue,
        InitiateOpenPositionData memory data
    ) internal returns (uint256 amountToRefund_) {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateOpenPosition,
            timestamp: uint40(block.timestamp),
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            tick: data.posId.tick,
            closeAmount: 0,
            closePosTotalExpo: 0,
            tickVersion: data.posId.tickVersion,
            index: data.posId.index,
            closeLiqMultiplier: 0,
            closeBoundedPositionValue: 0
        });
        amountToRefund_ = coreLib._addPendingAction(s, validator, coreLib._convertLongPendingAction(action));
    }

    /**
     * @notice Initiate an open position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data
     * @param params The parameters for the open position initiation
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @return posId_ The unique index of the opened position
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     */
    function _initiateOpenPosition(
        Storage storage s,
        InitiateOpenPositionParams memory params,
        bytes calldata currentPriceData
    ) internal returns (PositionId memory posId_, uint256 amountToRefund_, bool isInitiated_) {
        if (params.to == address(0)) {
            // revert UsdnProtocolInvalidAddressTo();
        }
        if (params.validator == address(0)) {
            // revert UsdnProtocolInvalidAddressValidator();
        }
        if (params.amount == 0) {
            // revert UsdnProtocolZeroAmount();
        }
        if (params.amount < s._minLongPosition) {
            // revert UsdnProtocolLongPositionTooSmall();
        }

        InitiateOpenPositionData memory data = _prepareInitiateOpenPositionData(
            s, params.validator, params.amount, params.desiredLiqPrice, currentPriceData
        );

        if (data.isLiquidationPending) {
            // value to indicate the position was not created
            posId_.tick = s.NO_POSITION_TICK;
            return (posId_, params.securityDepositValue, false);
        }

        // register position and adjust contract state
        Position memory long = Position({
            validated: false,
            user: params.to,
            amount: params.amount,
            totalExpo: data.positionTotalExpo,
            timestamp: uint40(block.timestamp)
        });
        (data.posId.tickVersion, data.posId.index,) =
            _saveNewPosition(s, data.posId.tick, long, data.liquidationPenalty);
        s._balanceLong += long.amount;
        posId_ = data.posId;

        amountToRefund_ = _createOpenPendingAction(s, params.to, params.validator, params.securityDepositValue, data);

        if (params.permit2TokenBitfield.useForAsset()) {
            address(s._asset).permit2TransferFrom(params.user, address(this), params.amount);
        } else {
            address(s._asset).safeTransferFrom(params.user, address(this), params.amount);
        }

        isInitiated_ = true;
        // emit InitiatedOpenPosition(
        //     params.to,
        //     params.validator,
        //     uint40(block.timestamp),
        //     data.positionTotalExpo,
        //     params.amount,
        //     data.adjustedPrice,
        //     posId_
        // );
    }

    /**
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateOpenPosition(Storage storage s, address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != ProtocolAction.ValidateOpenPosition) {
            // revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            // revert UsdnProtocolInvalidPendingAction();
        }
        (isValidated_, liquidated_) = _validateOpenPositionWithAction(s, pending, priceData);

        if (isValidated_ || liquidated_) {
            coreLib._clearPendingAction(s, validator, rawIndex);
            return (pending.securityDepositValue, isValidated_, liquidated_);
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the open position action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return data_ The {ValidateOpenPosition} data struct
     * @return liquidated_ Whether the position was liquidated
     */
    function _prepareValidateOpenPositionData(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        internal
        returns (ValidateOpenPositionData memory data_, bool liquidated_)
    {
        data_.action = coreLib._toLongPendingAction(pending);
        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.ValidateOpenPosition,
            data_.action.timestamp,
            _calcActionId(data_.action.validator, data_.action.timestamp),
            priceData
        );
        // apply fees on price
        data_.startPrice = (currentPrice.price + currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.ValidateOpenPosition,
            priceData
        );

        uint256 version;
        (data_.tickHash, version) = vaultLib._tickHash(s, data_.action.tick);
        if (version != data_.action.tickVersion) {
            // the current tick version doesn't match the version from the pending action
            // this means the position has been liquidated in the meantime
            // emit StalePendingActionRemoved(
            //     data_.action.validator,
            //     PositionId({ tick: data_.action.tick, tickVersion: data_.action.tickVersion, index:
            // data_.action.index })
            // );
            return (data_, true);
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        // get the position
        data_.pos = s._longPositions[data_.tickHash][data_.action.index];
        // re-calculate leverage
        data_.liquidationPenalty = s._tickData[data_.tickHash].liquidationPenalty;
        data_.liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
            s, longLib._calcTickWithoutPenalty(s, data_.action.tick, data_.liquidationPenalty)
        );
        // reverts if liqPriceWithoutPenalty >= startPrice
        data_.leverage = longLib._getLeverage(s, data_.startPrice, data_.liqPriceWithoutPenalty);
    }

    /**
     * @notice Validate an open position action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateOpenPositionWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_, bool liquidated_)
    {
        (ValidateOpenPositionData memory data, bool liquidated) =
            _prepareValidateOpenPositionData(s, pending, priceData);

        if (liquidated) {
            return (!data.isLiquidationPending, true);
        }

        if (data.isLiquidationPending) {
            return (false, false);
        }

        // leverage is always greater than one (`liquidationPrice` is positive)
        // even if it drops below _minLeverage between the initiate and validate actions, we still allow it
        // however, if the leverage exceeds max leverage, then we adjust the liquidation price (tick) to have a leverage
        // of _maxLeverage
        uint128 maxLeverage = uint128(s._maxLeverage);
        if (data.leverage > maxLeverage) {
            // theoretical liquidation price for _maxLeverage
            data.liqPriceWithoutPenalty = longLib._getLiquidationPrice(s, data.startPrice, maxLeverage);
            // adjust to the closest valid tick down
            int24 tickWithoutPenalty = longLib.getEffectiveTickForPrice(s, data.liqPriceWithoutPenalty);

            // apply liquidation penalty with the current penalty setting
            uint8 currentLiqPenalty = s._liquidationPenalty;
            PositionId memory newPosId;
            newPosId.tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * s._tickSpacing;
            // retrieve the actual penalty for this tick we want to use
            uint8 liquidationPenalty = longLib.getTickLiquidationPenalty(s, newPosId.tick);
            // check if the penalty for that tick is different from the current setting
            if (liquidationPenalty == currentLiqPenalty) {
                // since the tick's penalty is the same as what we assumed, we can use the `tickWithoutPenalty` from
                // above
                // retrieve the exact liquidation price without penalty
                data.liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(s, tickWithoutPenalty);
            } else {
                // the tick's imposed penalty is different from the current setting, so the `tickWithoutPenalty` we
                // calculated above can't be used to calculate the leverage
                // we must instead use the tick's penalty to find the new `liqPriceWithoutPenalty` and calculate the
                // leverage

                // note: In case the tick liquidation penalty is lower than the current setting, it might lead to a
                // leverage that exceeds the max leverage slightly. We allow this behavior in this rare occurrence

                // retrieve exact liquidation price without penalty
                data.liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
                    s, longLib._calcTickWithoutPenalty(s, newPosId.tick, liquidationPenalty)
                );
            }

            // move the position to its new tick, update its total expo, and return the new tickVersion and index
            // remove position from old tick completely
            _removeAmountFromPosition(
                s, data.action.tick, data.action.index, data.pos, data.pos.amount, data.pos.totalExpo
            );
            // update position total expo (because of new leverage / liq price)
            data.pos.totalExpo =
                longLib._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);
            // mark the position as validated
            data.pos.validated = true;
            // insert position into new tick
            (newPosId.tickVersion, newPosId.index,) = _saveNewPosition(s, newPosId.tick, data.pos, liquidationPenalty);
            // no long balance update is necessary (collateral didn't change)

            // emit LiquidationPriceUpdated
            // emit LiquidationPriceUpdated(
            //     PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index
            // }),
            //     newPosId
            // );
            // emit ValidatedOpenPosition(
            //     data.action.to, data.action.validator, data.pos.totalExpo, data.startPrice, newPosId
            // );

            return (true, false);
        }
        // calculate the new total expo
        uint128 expoBefore = data.pos.totalExpo;
        uint128 expoAfter =
            longLib._calcPositionTotalExpo(data.pos.amount, data.startPrice, data.liqPriceWithoutPenalty);

        // update the total expo of the position
        data.pos.totalExpo = expoAfter;
        // mark the position as validated
        data.pos.validated = true;
        // SSTORE
        s._longPositions[data.tickHash][data.action.index] = data.pos;
        // update the total expo by adding the position's new expo and removing the old one
        // do not use += or it will underflow
        s._totalExpo = s._totalExpo + expoAfter - expoBefore;

        // update the tick data and the liqMultiplierAccumulator
        {
            TickData storage tickData = s._tickData[data.tickHash];
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.action.tick - int24(uint24(data.liquidationPenalty)) * s._tickSpacing);
            tickData.totalExpo = tickData.totalExpo + expoAfter - expoBefore;
            s._liqMultiplierAccumulator = s._liqMultiplierAccumulator.add(
                HugeUint.wrap(expoAfter * unadjustedTickPrice)
            ).sub(HugeUint.wrap(expoBefore * unadjustedTickPrice));
        }

        isValidated_ = true;
        // emit ValidatedOpenPosition(
        //     data.action.to,
        //     data.action.validator,
        //     expoAfter,
        //     data.startPrice,
        //     PositionId({ tick: data.action.tick, tickVersion: data.action.tickVersion, index: data.action.index })
        // );
    }

    /**
     * @notice Perform checks for the initiate close position action
     * @dev Reverts if the to address is zero, the position was not validated yet, the position is not owned by the
     * user, the amount to close is higher than the position amount, or the amount to close is zero
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address of the validator
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param pos The position to close
     */
    function _checkInitiateClosePosition(
        Storage storage s,
        address owner,
        address to,
        address validator,
        uint128 amountToClose,
        Position memory pos
    ) internal view {
        if (to == address(0)) {
            // revert UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            // revert UsdnProtocolInvalidAddressValidator();
        }
        if (pos.user != owner) {
            // revert UsdnProtocolUnauthorized();
        }
        if (!pos.validated) {
            // revert UsdnProtocolPositionNotValidated();
        }
        if (amountToClose > pos.amount) {
            // revert UsdnProtocolAmountToCloseHigherThanPositionAmount(amountToClose, pos.amount);
        }

        // make sure the remaining position is higher than _minLongPosition
        // for the Rebalancer, we allow users to close their position fully in every case
        uint128 remainingAmount = pos.amount - amountToClose;
        if (remainingAmount > 0 && remainingAmount < s._minLongPosition) {
            IBaseRebalancer rebalancer = s._rebalancer;
            if (owner == address(rebalancer)) {
                uint128 userPosAmount = rebalancer.getUserDepositData(to).amount;
                if (amountToClose != userPosAmount) {
                    // revert UsdnProtocolLongPositionTooSmall();
                }
            } else {
                // revert UsdnProtocolLongPositionTooSmall();
            }
        }
        if (amountToClose == 0) {
            // revert UsdnProtocolAmountToCloseIsZero();
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the initiate close position action
     * @dev Reverts if the imbalance limit is reached, or if any of the checks in `_checkInitiateClosePosition` fail
     * Returns without creating a pending action if the position gets liquidated in this transaction
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address of the pending action validator
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @return data_ The close position data
     * @return liquidated_ Whether the position was liquidated and the caller should return early
     */
    function _prepareClosePositionData(
        Storage storage s,
        address owner,
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        bytes calldata currentPriceData
    ) internal returns (ClosePositionData memory data_, bool liquidated_) {
        (data_.pos, data_.liquidationPenalty) = longLib.getLongPosition(s, posId);

        _checkInitiateClosePosition(s, owner, to, validator, amountToClose, data_.pos);

        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.InitiateClosePosition,
            block.timestamp,
            _calcActionId(owner, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.InitiateClosePosition,
            currentPriceData
        );

        uint256 version = s._tickVersion[posId.tick];
        if (version != posId.tickVersion) {
            // the current tick version doesn't match the version from the position,
            // that means that the position has been liquidated in this transaction
            return (data_, true);
        }

        if (data_.isLiquidationPending) {
            return (data_, false);
        }

        data_.totalExpoToClose = (uint256(data_.pos.totalExpo) * amountToClose / data_.pos.amount).toUint128();

        data_.longTradingExpo = s._totalExpo - s._balanceLong;
        data_.liqMulAcc = s._liqMultiplierAccumulator;
        data_.lastPrice = s._lastPrice;

        // the approximate value position to remove is calculated with `_lastPrice`, so not taking into account
        // any fees. This way, the removal of the position doesn't affect the liquidation multiplier calculations

        // to have maximum precision, we do not pre-compute the liquidation multiplier with a fixed
        // precision just now, we will store it in the pending action later, to be used in the validate action
        data_.tempPositionValue = _assetToRemove(
            s,
            data_.lastPrice,
            longLib.getEffectivePriceForTick(
                longLib._calcTickWithoutPenalty(s, posId.tick, data_.liquidationPenalty),
                data_.lastPrice,
                data_.longTradingExpo,
                data_.liqMulAcc
            ),
            data_.totalExpoToClose
        );

        // we perform the imbalance check based on the estimated balance change since that's the best we have right now
        _checkImbalanceLimitClose(s, data_.totalExpoToClose, data_.tempPositionValue);
    }

    /**
     * @notice Prepare the pending action struct for the close position action and add it to the queue
     * @param validator The validator for the pending action
     * @param to The address that will receive the assets
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The close position data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createClosePendingAction(
        Storage storage s,
        address validator,
        address to,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        ClosePositionData memory data
    ) internal returns (uint256 amountToRefund_) {
        LongPendingAction memory action = LongPendingAction({
            action: ProtocolAction.ValidateClosePosition,
            timestamp: uint40(block.timestamp),
            to: to,
            validator: validator,
            securityDepositValue: securityDepositValue,
            tick: posId.tick,
            closeAmount: amountToClose,
            closePosTotalExpo: data.totalExpoToClose,
            tickVersion: posId.tickVersion,
            index: posId.index,
            closeLiqMultiplier: longLib._calcFixedPrecisionMultiplier(
                s, data.lastPrice, data.longTradingExpo, data.liqMulAcc
            ),
            closeBoundedPositionValue: data.tempPositionValue
        });
        amountToRefund_ = coreLib._addPendingAction(s, validator, coreLib._convertLongPendingAction(action));
    }

    /**
     * @notice Initiate a close position action
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and this function will return 0
     * The position is taken out of the tick and put in a pending state during this operation. Thus, calculations don't
     * consider this position anymore. The exit price (and thus profit) is not yet set definitively and will be done
     * during the `validate` action
     * @param owner The owner of the position
     * @param to The address that will receive the assets
     * @param validator The address that will validate the close action
     * @param posId The unique identifier of the position
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     * @return liquidated_ Whether the position was liquidated
     */
    function _initiateClosePosition(
        Storage storage s,
        address owner,
        address to,
        address validator,
        PositionId memory posId,
        uint128 amountToClose,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) internal returns (uint256 amountToRefund_, bool isInitiated_, bool liquidated_) {
        ClosePositionData memory data;
        (data, liquidated_) = _prepareClosePositionData(s, owner, to, validator, posId, amountToClose, currentPriceData);

        if (liquidated_ || data.isLiquidationPending) {
            // position was liquidated in this transaction or liquidations are pending
            return (securityDepositValue, !data.isLiquidationPending, liquidated_);
        }

        amountToRefund_ = _createClosePendingAction(s, validator, to, posId, amountToClose, securityDepositValue, data);

        s._balanceLong -= data.tempPositionValue;

        _removeAmountFromPosition(s, posId.tick, posId.index, data.pos, amountToClose, data.totalExpoToClose);

        isInitiated_ = true;
        // emit InitiatedClosePosition(
        //     data.pos.user,
        //     validator,
        //     to,
        //     posId,
        //     data.pos.amount,
        //     amountToClose,
        //     data.pos.totalExpo - data.totalExpoToClose
        // );
    }

    /**
     * @notice Get the pending action data of the validator, try to validate it and clear it if successful
     * @param validator The validator of the pending action
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit of the pending action
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateClosePosition(Storage storage s, address validator, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_, bool isValidated_, bool liquidated_)
    {
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != ProtocolAction.ValidateClosePosition) {
            // revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            // revert UsdnProtocolInvalidPendingAction();
        }

        (isValidated_, liquidated_) = _validateClosePositionWithAction(s, pending, priceData);

        if (isValidated_ || liquidated_) {
            coreLib._clearPendingAction(s, validator, rawIndex);
            return (pending.securityDepositValue, isValidated_, liquidated_);
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the close position action
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     * @return liquidated_ Whether the pending action has been liquidated
     */
    function _validateClosePositionWithAction(Storage storage s, PendingAction memory pending, bytes calldata priceData)
        internal
        returns (bool isValidated_, bool liquidated_)
    {
        LongPendingAction memory long = coreLib._toLongPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            ProtocolAction.ValidateClosePosition,
            long.timestamp,
            _calcActionId(long.validator, long.timestamp),
            priceData
        );

        (, bool isLiquidationPending) = _applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            ProtocolAction.ValidateClosePosition,
            priceData
        );

        // apply fees on price
        uint128 priceWithFees =
            (currentPrice.price - currentPrice.price * s._positionFeeBps / s.BPS_DIVISOR).toUint128();

        // get liquidation price (with liq penalty) to check if the position was valid at `timestamp + validationDelay`
        uint128 liquidationPrice = longLib._getEffectivePriceForTick(s, long.tick, long.closeLiqMultiplier);

        if (currentPrice.neutralPrice <= liquidationPrice) {
            // position should be liquidated, we don't transfer assets to the user
            // position was already removed from tick so no additional bookkeeping is necessary
            // credit the full amount to the vault to preserve the total balance invariant
            s._balanceVault += long.closeBoundedPositionValue;
            // emit LiquidatedPosition(
            //     long.validator, // not necessarily the position owner
            //     PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
            //     currentPrice.neutralPrice,
            //     liquidationPrice
            // );
            return (!isLiquidationPending, true);
        }

        if (isLiquidationPending) {
            return (false, false);
        }

        int256 positionValue = longLib._positionValue(
            priceWithFees,
            longLib._getEffectivePriceForTick(
                s,
                longLib._calcTickWithoutPenalty(s, long.tick, longLib.getTickLiquidationPenalty(s, long.tick)),
                long.closeLiqMultiplier
            ),
            long.closePosTotalExpo
        );
        uint256 assetToTransfer;
        if (positionValue > 0) {
            assetToTransfer = uint256(positionValue);
            // normally, the position value should be smaller than `long.closeBoundedPositionValue` (due to the position
            // fee)
            // we can send the difference (any remaining collateral) to the vault
            // if the price increased since the initiation, it's possible that the position value is higher than the
            // `long.closeBoundedPositionValue`. In that case, we need to take the missing assets from the vault
            if (assetToTransfer < long.closeBoundedPositionValue) {
                uint256 remainingCollateral;
                unchecked {
                    // since assetToTransfer is strictly smaller than closeBoundedPositionValue, this operation can't
                    // underflow
                    remainingCollateral = long.closeBoundedPositionValue - assetToTransfer;
                }
                s._balanceVault += remainingCollateral;
            } else if (assetToTransfer > long.closeBoundedPositionValue) {
                uint256 missingValue;
                unchecked {
                    // since assetToTransfer is strictly larger than closeBoundedPositionValue, this operation can't
                    // underflow
                    missingValue = assetToTransfer - long.closeBoundedPositionValue;
                }
                uint256 balanceVault = s._balanceVault;
                // if the vault does not have enough balance left to pay out the missing value, we take what we can
                if (missingValue > balanceVault) {
                    s._balanceVault = 0;
                    unchecked {
                        // since `missingValue` is strictly larger than `balanceVault`, their subtraction can't
                        // underflow
                        // moreover, since (missingValue - balanceVault) is smaller than or equal to `missingValue`,
                        // and since `missingValue` is smaller than or equal to `assetToTransfer`,
                        // (missingValue - balanceVault) is smaller than or equal to `assetToTransfer`, and their
                        // subtraction can't underflow
                        assetToTransfer -= missingValue - balanceVault;
                    }
                } else {
                    unchecked {
                        // as `missingValue` is smaller than or equal to `balanceVault`, this operation can't underflow
                        s._balanceVault = balanceVault - missingValue;
                    }
                }
            }
        }
        // in case the position value is zero or negative, we don't transfer any asset to the user

        // send the asset to the user
        if (assetToTransfer > 0) {
            address(s._asset).safeTransfer(long.to, assetToTransfer);
        }

        isValidated_ = true;

        // emit ValidatedClosePosition(
        //     long.validator, // not necessarily the position owner
        //     long.to,
        //     PositionId({ tick: long.tick, tickVersion: long.tickVersion, index: long.index }),
        //     assetToTransfer,
        //     assetToTransfer.toInt256() - _toInt256(long.closeAmount)
        // );
    }

    /**
     * @notice Reverts if the position's leverage is higher than max or lower than min
     * @param adjustedPrice The adjusted price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     */
    function _checkOpenPositionLeverage(Storage storage s, uint128 adjustedPrice, uint128 liqPriceWithoutPenalty)
        internal
        view
    {
        // calculate position leverage
        // reverts if liquidationPrice >= entryPrice
        uint128 leverage = longLib._getLeverage(s, adjustedPrice, liqPriceWithoutPenalty);
        if (leverage < s._minLeverage) {
            // revert UsdnProtocolLeverageTooLow();
        }
        if (leverage > s._maxLeverage) {
            // revert UsdnProtocolLeverageTooHigh();
        }
    }

    /**
     * @notice Calculate how much wstETH must be removed from the long balance due to a position closing
     * @dev The amount is bound by the amount of wstETH available on the long side
     * @param priceWithFees The current price of the asset, adjusted with fees
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @param posExpo The total expo of the position
     * @return boundedPosValue_ The amount of assets to remove from the long balance, bound by zero and the available
     * long balance
     */
    function _assetToRemove(Storage storage s, uint128 priceWithFees, uint128 liqPriceWithoutPenalty, uint128 posExpo)
        internal
        view
        returns (uint256 boundedPosValue_)
    {
        // the available amount of assets on the long side (with the current balance)
        uint256 available = s._balanceLong;

        // calculate position value
        int256 positionValue = longLib._positionValue(priceWithFees, liqPriceWithoutPenalty, posExpo);

        if (positionValue <= 0) {
            // should not happen, unless we did not manage to liquidate all ticks that needed to be liquidated during
            // the initiateClosePosition
            boundedPosValue_ = 0;
        } else if (uint256(positionValue) > available) {
            boundedPosValue_ = available;
        } else {
            boundedPosValue_ = uint256(positionValue);
        }
    }

    /**
     * @notice Execute the first actionable pending action or revert if the price data was not provided
     * @param data The price data and raw indices
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingActionOrRevert(Storage storage s, PreviousActionsData calldata data)
        internal
        returns (uint256 securityDepositValue_)
    {
        bool success;
        (success,,, securityDepositValue_) = _executePendingAction(s, data);
        if (!success) {
            // revert UsdnProtocolInvalidPendingActionData();
        }
    }

    /**
     * @notice Execute the first actionable pending action and report the success
     * @param data The price data and raw indices
     * @return success_ Whether the price data is valid
     * @return executed_ Whether the pending action was executed (false if the queue has no actionable item)
     * @return liquidated_ Whether the position corresponding to the pending action was liquidated
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingAction(Storage storage s, PreviousActionsData calldata data)
        internal
        returns (bool success_, bool executed_, bool liquidated_, uint256 securityDepositValue_)
    {
        (PendingAction memory pending, uint128 rawIndex) = coreLib._getActionablePendingAction(s);
        if (pending.action == ProtocolAction.None) {
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
        if (pending.action == ProtocolAction.ValidateDeposit) {
            executed_ = _validateDepositWithAction(s, pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateWithdrawal) {
            executed_ = _validateWithdrawalWithAction(s, pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateOpenPosition) {
            (executed_, liquidated_) = _validateOpenPositionWithAction(s, pending, priceData);
        } else if (pending.action == ProtocolAction.ValidateClosePosition) {
            (executed_, liquidated_) = _validateClosePositionWithAction(s, pending, priceData);
        }

        success_ = true;

        if (executed_ || liquidated_) {
            coreLib._clearPendingAction(s, pending.validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
            // emit SecurityDepositRefunded(pending.validator, msg.sender, securityDepositValue_);
        }
    }

    /**
     * @notice Get the oracle price for the given action and timestamp then validate it
     * @param action The type of action that is being performed by the user
     * @param timestamp The timestamp at which the wanted price was recorded
     * @param actionId The unique identifier of the action
     * @param priceData The price oracle data
     * @return price_ The validated price
     */
    function _getOraclePrice(
        Storage storage s,
        ProtocolAction action,
        uint256 timestamp,
        bytes32 actionId,
        bytes calldata priceData
    ) internal returns (PriceInfo memory price_) {
        uint256 validationCost = s._oracleMiddleware.validationCost(priceData, action);
        if (address(this).balance < validationCost) {
            // revert UsdnProtocolInsufficientOracleFee();
        }
        price_ = s._oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            actionId, uint128(timestamp), action, priceData
        );
    }

    /**
     * @notice Liquidate positions that have a liquidation price lower than the current price
     * @param currentPrice The current price of the asset
     * @param iteration The maximum number of ticks to liquidate (minimum is 1)
     * @param tempLongBalance The temporary long balance as calculated when applying the PnL and funding
     * @param tempVaultBalance The temporary vault balance as calculated when applying the PnL and funding
     * @return effects_ The effects of the liquidations on the protocol
     */
    function _liquidatePositions(
        Storage storage s,
        uint256 currentPrice,
        uint16 iteration,
        int256 tempLongBalance,
        int256 tempVaultBalance
    ) internal returns (LiquidationsEffects memory effects_) {
        int256 longTradingExpo = s._totalExpo.toInt256() - tempLongBalance;
        if (longTradingExpo <= 0) {
            // in case the long balance is equal to the total expo (or exceeds it), the trading expo will become zero
            // in this case, it's not possible to calculate the current tick, so we can't perform any liquidations
            (effects_.newLongBalance, effects_.newVaultBalance) =
                longLib._handleNegativeBalances(tempLongBalance, tempVaultBalance);
            return effects_;
        }

        LiquidationData memory data;
        data.tempLongBalance = tempLongBalance;
        data.tempVaultBalance = tempVaultBalance;
        data.longTradingExpo = uint256(longTradingExpo);
        data.currentPrice = currentPrice;
        data.accumulator = s._liqMultiplierAccumulator;

        // max iteration limit
        if (iteration > s.MAX_LIQUIDATION_ITERATION) {
            iteration = s.MAX_LIQUIDATION_ITERATION;
        }

        uint256 unadjustedPrice =
            longLib._unadjustPrice(data.currentPrice, data.currentPrice, data.longTradingExpo, data.accumulator);
        data.currentTick = TickMath.getClosestTickAtPrice(unadjustedPrice);
        data.iTick = s._highestPopulatedTick;

        do {
            uint256 index = s._tickBitmap.findLastSet(coreLib._calcBitmapIndexFromTick(s, data.iTick));
            if (index == LibBitmap.NOT_FOUND) {
                // no populated ticks left
                break;
            }

            data.iTick = longLib._calcTickFromBitmapIndex(s, index);
            if (data.iTick < data.currentTick) {
                // all ticks that can be liquidated have been processed
                break;
            }

            // we have found a non-empty tick that needs to be liquidated
            (bytes32 tickHash,) = vaultLib._tickHash(s, data.iTick);

            TickData memory tickData = s._tickData[tickHash];
            // update transient data
            data.totalExpoToRemove += tickData.totalExpo;
            uint256 unadjustedTickPrice =
                TickMath.getPriceAtTick(data.iTick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
            data.accumulatorValueToRemove += unadjustedTickPrice * tickData.totalExpo;
            // update return values
            effects_.liquidatedPositions += tickData.totalPos;
            ++effects_.liquidatedTicks;
            int256 tickValue =
                longLib._tickValue(s, data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator, tickData);
            effects_.remainingCollateral += tickValue;

            // reset tick by incrementing the tick version
            ++s._tickVersion[data.iTick];
            // update bitmap to reflect that the tick is empty
            s._tickBitmap.unset(index);

            // emit LiquidatedTick(
            //     data.iTick,
            //     s._tickVersion[data.iTick] - 1,
            //     data.currentPrice,
            //     getEffectivePriceForTick(data.iTick, data.currentPrice, data.longTradingExpo, data.accumulator),
            //     tickValue
            // );
        } while (effects_.liquidatedTicks < iteration);

        longLib._updateStateAfterLiquidation(s, data, effects_); // mutates `data`
        effects_.isLiquidationPending = data.isLiquidationPending;
        (effects_.newLongBalance, effects_.newVaultBalance) =
            longLib._handleNegativeBalances(data.tempLongBalance, data.tempVaultBalance);
    }

    /**
     * @notice Applies PnL, funding, and liquidates positions if necessary
     * @param neutralPrice The neutral price for the asset
     * @param timestamp The timestamp at which the operation is performed
     * @param iterations The number of iterations for the liquidation process
     * @param ignoreInterval A boolean indicating whether to ignore the interval for USDN rebase
     * @param action The type of action that is being performed by the user
     * @param priceData The price oracle update data
     * @return liquidatedPositions_ The number of positions that were liquidated
     * @return isLiquidationPending_ If there are pending positions to liquidate
     * @dev If there were any liquidated positions, it sends rewards to the msg.sender
     */
    function _applyPnlAndFundingAndLiquidate(
        Storage storage s,
        uint256 neutralPrice,
        uint256 timestamp,
        uint16 iterations,
        bool ignoreInterval,
        ProtocolAction action,
        bytes calldata priceData
    ) internal returns (uint256 liquidatedPositions_, bool isLiquidationPending_) {
        // adjust balances
        (bool isPriceRecent, int256 tempLongBalance, int256 tempVaultBalance) =
            _applyPnlAndFunding(s, neutralPrice.toUint128(), timestamp.toUint128());

        // liquidate if the price was updated or was already the most recent
        if (isPriceRecent) {
            LiquidationsEffects memory liquidationEffects =
                _liquidatePositions(s, s._lastPrice, iterations, tempLongBalance, tempVaultBalance);

            isLiquidationPending_ = liquidationEffects.isLiquidationPending;
            if (!isLiquidationPending_ && liquidationEffects.liquidatedTicks > 0) {
                if (s._closeExpoImbalanceLimitBps > 0) {
                    (liquidationEffects.newLongBalance, liquidationEffects.newVaultBalance) = _triggerRebalancer(
                        s,
                        s._lastPrice,
                        liquidationEffects.newLongBalance,
                        liquidationEffects.newVaultBalance,
                        liquidationEffects.remainingCollateral
                    );
                }
            }

            s._balanceLong = liquidationEffects.newLongBalance;
            s._balanceVault = liquidationEffects.newVaultBalance;

            (bool rebased, bytes memory callbackResult) = vaultLib._usdnRebase(s, s._lastPrice, ignoreInterval);

            if (liquidationEffects.liquidatedTicks > 0) {
                _sendRewardsToLiquidator(
                    s,
                    liquidationEffects.liquidatedTicks,
                    liquidationEffects.remainingCollateral,
                    rebased,
                    action,
                    callbackResult,
                    priceData
                );
            }

            liquidatedPositions_ = liquidationEffects.liquidatedPositions;
        }
    }

    /**
     * TODO add tests
     * @notice Trigger the rebalancer if the imbalance on the long side is too high
     * It will close the rebalancer position (if there is one) and open a new one with
     * the pending assets, the value of the previous position and the liquidation bonus (if available)
     * and a leverage to fill enough trading expo to reach the desired imbalance, up to the max leverages
     * @dev Will return the provided long balance if no rebalancer is set or if the imbalance is not high enough
     * @param lastPrice The last price used to update the protocol
     * @param longBalance The balance of the long side
     * @param vaultBalance The balance of the vault side
     * @param remainingCollateral The collateral remaining after the liquidations
     * @return longBalance_ The temporary balance of the long side
     * @return vaultBalance_ The temporary balance of the vault side
     */
    function _triggerRebalancer(
        Storage storage s,
        uint128 lastPrice,
        uint256 longBalance,
        uint256 vaultBalance,
        int256 remainingCollateral
    ) internal returns (uint256 longBalance_, uint256 vaultBalance_) {
        longBalance_ = longBalance;
        vaultBalance_ = vaultBalance;
        IBaseRebalancer rebalancer = s._rebalancer;

        if (address(rebalancer) == address(0)) {
            return (longBalance_, vaultBalance_);
        }

        CachedProtocolState memory cache = CachedProtocolState({
            totalExpo: s._totalExpo,
            longBalance: longBalance,
            vaultBalance: (vaultBalance.toInt256() + s._pendingBalanceVault).toUint256(),
            tradingExpo: 0,
            liqMultiplierAccumulator: s._liqMultiplierAccumulator
        });

        if (cache.totalExpo < cache.longBalance) {
            // revert UsdnProtocolInvalidLongExpo();
        }

        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        {
            int256 currentImbalance = longLib._calcImbalanceCloseBps(
                s, cache.vaultBalance.toInt256(), cache.longBalance.toInt256(), cache.totalExpo
            );

            // if the imbalance is lower than the threshold, return
            if (currentImbalance < s._closeExpoImbalanceLimitBps) {
                return (longBalance_, vaultBalance_);
            }
        }

        // the default value of `positionAmount` is the amount of pendingAssets in the rebalancer
        (uint128 positionAmount, uint256 rebalancerMaxLeverage, PositionId memory rebalancerPosId) =
            rebalancer.getCurrentStateData();

        uint128 positionValue;
        // close the rebalancer position and get its value to open the next one
        if (rebalancerPosId.tick != s.NO_POSITION_TICK) {
            // cached values will be updated during this call
            int256 realPositionValue = _flashClosePosition(s, rebalancerPosId, lastPrice, cache);

            // if the position value is less than 0, it should have been liquidated but wasn't
            // interrupt the whole rebalancer process because there are pending liquidations
            if (realPositionValue < 0) {
                return (longBalance_, vaultBalance_);
            }

            // cast is safe as realPositionValue cannot be lower than 0
            positionValue = uint256(realPositionValue).toUint128();
            positionAmount += positionValue;
        }

        // If there are no pending assets and the previous position was either liquidated or doesn't exist, return
        if (positionAmount + positionValue == 0) {
            return (longBalance_, vaultBalance_);
        }

        // transfer the pending assets from the rebalancer to this contract
        address(s._asset).safeTransferFrom(address(rebalancer), address(this), positionAmount - positionValue);

        // if there is enough collateral remaining after liquidations, calculate the bonus and add it to the
        // new rebalancer position
        if (remainingCollateral > 0) {
            uint128 bonus = (uint256(remainingCollateral) * s._rebalancerBonusBps / s.BPS_DIVISOR).toUint128();
            cache.vaultBalance -= bonus;
            vaultBalance_ -= bonus;
            positionAmount += bonus;
        }

        int24 tickWithoutLiqPenalty =
            longLib._calcRebalancerPositionTick(s, lastPrice, positionAmount, rebalancerMaxLeverage, cache);

        // make sure that the rebalancer was not triggered without a sufficient imbalance
        // as we check the imbalance above, this should not happen
        if (tickWithoutLiqPenalty == s.NO_POSITION_TICK) {
            // revert UsdnProtocolInvalidRebalancerTick();
        }

        // open a new position for the rebalancer
        PositionId memory posId =
            _flashOpenPosition(s, address(rebalancer), lastPrice, tickWithoutLiqPenalty, positionAmount, cache);

        longBalance_ += positionAmount;

        // call the rebalancer to update the internal bookkeeping
        rebalancer.updatePosition(posId, positionValue);
    }

    /**
     * @notice Immediately close a position with the given price
     * @dev Should only be used to close the rebalancer position
     * @param posId The ID of the position to close
     * @param lastPrice The last price used to update the protocol
     * @param cache The cached state of the protocol, will be updated during this call
     * @return positionValue_ The value of the closed position
     */
    function _flashClosePosition(
        Storage storage s,
        PositionId memory posId,
        uint128 lastPrice,
        CachedProtocolState memory cache
    ) internal returns (int256 positionValue_) {
        (bytes32 tickHash, uint256 version) = vaultLib._tickHash(s, posId.tick);
        // if the tick version is outdated, the position was liquidated and its value is 0
        if (posId.tickVersion != version) {
            return positionValue_;
        }

        uint8 liquidationPenalty = s._tickData[tickHash].liquidationPenalty;
        Position memory pos = s._longPositions[tickHash][posId.index];

        positionValue_ = longLib._positionValue(
            lastPrice,
            longLib.getEffectivePriceForTick(
                longLib._calcTickWithoutPenalty(s, posId.tick, liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            ),
            pos.totalExpo
        );

        // if positionValue is lower than 0, return
        if (positionValue_ < 0) {
            return positionValue_;
        }

        // fully close the position and update the cache
        cache.liqMultiplierAccumulator =
            _removeAmountFromPosition(s, posId.tick, posId.index, pos, pos.amount, pos.totalExpo);

        // update the cache
        cache.totalExpo -= pos.totalExpo;
        // cast is safe as positionValue cannot be lower than 0
        cache.longBalance -= uint256(positionValue_);
        cache.tradingExpo = cache.totalExpo - cache.longBalance;

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        // emit InitiatedClosePosition(pos.user, pos.user, pos.user, posId, pos.amount, pos.amount, 0);
        // emit ValidatedClosePosition(
        //     pos.user, pos.user, posId, uint256(positionValue_), positionValue_ - _toInt256(pos.amount)
        // );
    }

    /**
     * @notice Remove the provided total amount from its position and update the tick data and position
     * @dev Note: this method does not update the long balance
     * If the amount to remove is greater than or equal to the position's total amount, the position is deleted instead
     * @param tick The tick to remove from
     * @param index Index of the position in the tick array
     * @param pos The position to remove the amount from
     * @param amountToRemove The amount to remove from the position
     * @param totalExpoToRemove The total expo to remove from the position
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _removeAmountFromPosition(
        Storage storage s,
        int24 tick,
        uint256 index,
        Position memory pos,
        uint128 amountToRemove,
        uint128 totalExpoToRemove
    ) internal returns (HugeUint.Uint512 memory liqMultiplierAccumulator_) {
        (bytes32 tickHash,) = vaultLib._tickHash(s, tick);
        TickData storage tickData = s._tickData[tickHash];
        uint256 unadjustedTickPrice =
            TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
        if (amountToRemove < pos.amount) {
            Position storage position = s._longPositions[tickHash][index];
            position.totalExpo = pos.totalExpo - totalExpoToRemove;

            unchecked {
                position.amount = pos.amount - amountToRemove;
            }
        } else {
            totalExpoToRemove = pos.totalExpo;
            tickData.totalPos -= 1;
            --s._totalLongPositions;

            // remove from tick array (set to zero to avoid shifting indices)
            delete s._longPositions[tickHash][index];
            if (tickData.totalPos == 0) {
                // we removed the last position in the tick
                s._tickBitmap.unset(coreLib._calcBitmapIndexFromTick(s, tick));
            }
        }

        s._totalExpo -= totalExpoToRemove;
        tickData.totalExpo -= totalExpoToRemove;
        liqMultiplierAccumulator_ =
            s._liqMultiplierAccumulator.sub(HugeUint.wrap(unadjustedTickPrice * totalExpoToRemove));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Immediately open a position with the given price
     * @dev Should only be used to open the rebalancer position
     * @param user The address of the user
     * @param lastPrice The last price used to update the protocol
     * @param tickWithoutPenalty The tick the position should be opened in
     * @param amount The amount of collateral in the position
     * @param cache The cached state of the protocol
     * @return posId_ The ID of the position that was created
     */
    function _flashOpenPosition(
        Storage storage s,
        address user,
        uint128 lastPrice,
        int24 tickWithoutPenalty,
        uint128 amount,
        CachedProtocolState memory cache
    ) internal returns (PositionId memory posId_) {
        // we calculate the closest valid tick down for the desired liquidation price with the liquidation penalty
        uint8 currentLiqPenalty = s._liquidationPenalty;

        posId_.tick = tickWithoutPenalty + int24(uint24(currentLiqPenalty)) * s._tickSpacing;

        uint8 liquidationPenalty = longLib.getTickLiquidationPenalty(s, posId_.tick);
        uint128 liqPriceWithoutPenalty;

        // check if the penalty for that tick is different from the current setting
        // this can happen if the setting has been changed, but the position is added in a tick that was never empty
        // after the said change, so the first value is still applied
        if (liquidationPenalty == currentLiqPenalty) {
            liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
                tickWithoutPenalty, lastPrice, cache.tradingExpo, cache.liqMultiplierAccumulator
            );
        } else {
            liqPriceWithoutPenalty = longLib.getEffectivePriceForTick(
                longLib._calcTickWithoutPenalty(s, posId_.tick, liquidationPenalty),
                lastPrice,
                cache.tradingExpo,
                cache.liqMultiplierAccumulator
            );
        }

        uint128 totalExpo = longLib._calcPositionTotalExpo(amount, lastPrice, liqPriceWithoutPenalty);
        Position memory long = Position({
            validated: true,
            user: user,
            amount: amount,
            totalExpo: totalExpo,
            timestamp: uint40(block.timestamp)
        });

        // save the position on the provided tick
        (posId_.tickVersion, posId_.index,) = _saveNewPosition(s, posId_.tick, long, liquidationPenalty);

        // emit both initiate and validate events
        // so the position is considered the same as other positions by event indexers
        // emit InitiatedOpenPosition(user, user, uint40(block.timestamp), totalExpo, long.amount, lastPrice, posId_);
        // emit ValidatedOpenPosition(user, user, totalExpo, lastPrice, posId_);
    }

    /**
     * @notice Save a new position in the protocol, adjusting the tick data and global variables
     * @dev Note: this method does not update the long balance
     * @param tick The tick to hold the new position
     * @param long The position to save
     * @param liquidationPenalty The liquidation penalty for the tick
     * @return tickVersion_ The version of the tick
     * @return index_ The index of the position in the tick array
     * @return liqMultiplierAccumulator_ The updated liquidation multiplier accumulator
     */
    function _saveNewPosition(Storage storage s, int24 tick, Position memory long, uint8 liquidationPenalty)
        internal
        returns (uint256 tickVersion_, uint256 index_, HugeUint.Uint512 memory liqMultiplierAccumulator_)
    {
        bytes32 tickHash;
        (tickHash, tickVersion_) = vaultLib._tickHash(s, tick);

        // add to tick array
        Position[] storage tickArray = s._longPositions[tickHash];
        index_ = tickArray.length;
        if (tick > s._highestPopulatedTick) {
            // keep track of the highest populated tick
            s._highestPopulatedTick = tick;
        }
        tickArray.push(long);

        // adjust state
        s._totalExpo += long.totalExpo;
        ++s._totalLongPositions;

        // update tick data
        TickData storage tickData = s._tickData[tickHash];
        // the unadjusted tick price for the accumulator might be different depending
        // if we already have positions in the tick or not
        uint256 unadjustedTickPrice;
        if (tickData.totalPos == 0) {
            // first position in this tick, we need to reflect that it is populated
            s._tickBitmap.set(coreLib._calcBitmapIndexFromTick(s, tick));
            // we store the data for this tick
            tickData.totalExpo = long.totalExpo;
            tickData.totalPos = 1;
            tickData.liquidationPenalty = liquidationPenalty;
            unadjustedTickPrice = TickMath.getPriceAtTick(tick - int24(uint24(liquidationPenalty)) * s._tickSpacing);
        } else {
            tickData.totalExpo += long.totalExpo;
            tickData.totalPos += 1;
            // we do not need to adjust the tick's `liquidationPenalty` since it remains constant
            unadjustedTickPrice =
                TickMath.getPriceAtTick(tick - int24(uint24(tickData.liquidationPenalty)) * s._tickSpacing);
        }
        // update the accumulator with the correct tick price (depending on the liquidation penalty value)
        liqMultiplierAccumulator_ = s._liqMultiplierAccumulator.add(HugeUint.wrap(unadjustedTickPrice * long.totalExpo));
        s._liqMultiplierAccumulator = liqMultiplierAccumulator_;
    }

    /**
     * @notice Refunds any excess ether to the user to prevent locking ETH in the contract
     * @param securityDepositValue The security deposit value of the action (zero for a validation action)
     * @param amountToRefund The amount to refund to the user:
     *      - the security deposit if executing an action for another user,
     *      - the initialization security deposit in case of a validation action
     * @param balanceBefore The balance of the contract before the action
     */
    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) internal {
        uint256 positive = amountToRefund + address(this).balance + msg.value;
        uint256 negative = balanceBefore + securityDepositValue;

        if (negative > positive) {
            // revert UsdnProtocolUnexpectedBalance();
        }

        uint256 amount;
        unchecked {
            // we know that positive >= negative, so this subtraction is safe
            amount = positive - negative;
        }

        _refundEther(amount, payable(msg.sender));
    }

    /**
     * @notice Refunds an amount of ether to the given address
     * @param amount The amount of ether to refund
     * @param to The address that should receive the refund
     */
    function _refundEther(uint256 amount, address payable to) internal {
        if (to == address(0)) {
            // revert UsdnProtocolInvalidAddressTo();
        }
        if (amount != 0) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = to.call{ value: amount }("");
            if (!success) {
                // revert UsdnProtocolEtherRefundFailed();
            }
        }
    }

    /**
     * @notice Distribute the protocol fee to the fee collector if it exceeds the threshold
     * @dev This function is called after every action that changes the protocol fee balance
     */
    function _checkPendingFee(Storage storage s) internal {
        if (s._pendingProtocolFee >= s._feeThreshold) {
            address(s._asset).safeTransfer(s._feeCollector, s._pendingProtocolFee);
            // emit ProtocolFeeDistributed(_feeCollector, s._pendingProtocolFee);
            s._pendingProtocolFee = 0;
        }
    }

    /**
     * @notice Calculate a unique identifier for a pending action, that can be used by the oracle middleware to link
     * a `Initiate` call with the corresponding `Validate` call
     * @param validator The address of the validator
     * @param initiateTimestamp The timestamp of the initiate action
     * @return actionId_ The unique action ID
     */
    function _calcActionId(address validator, uint128 initiateTimestamp) internal pure returns (bytes32 actionId_) {
        actionId_ = keccak256(abi.encodePacked(validator, initiateTimestamp));
    }
}
