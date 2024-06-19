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
import { Storage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolVaultLibrary as vaultLib } from "./UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as longLib } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolActionsLibrary as actionsLongLib } from "./UsdnProtocolActionsLibrary.sol";
import { IUsdnProtocolErrors } from "./../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

struct InitiateClosePositionParams {
    PositionId posId;
    uint128 amountToClose;
    address to;
    address payable validator;
}

/**
 * @notice Emitted when a position changes ownership
 * @param posId The unique position ID
 * @param oldOwner The old owner
 * @param newOwner The new owner
 */
event PositionOwnershipTransferred(PositionId indexed posId, address indexed oldOwner, address indexed newOwner);

/**
 * @notice Emitted when a position is individually liquidated
 * @param user The validator of the close action, not necessarily the owner of the position
 * @param posId The unique identifier for the position that was liquidated
 * @param liquidationPrice The asset price at the moment of liquidation
 * @param effectiveTickPrice The effective liquidated tick price
 */
event LiquidatedPosition(address indexed user, PositionId posId, uint256 liquidationPrice, uint256 effectiveTickPrice);

/**
 * @notice Emitted when a user (liquidator) successfully liquidated positions
 * @param liquidator The address that initiated the liquidation
 * @param rewards The amount of tokens the liquidator received in rewards
 */
event LiquidatorRewarded(address indexed liquidator, uint256 rewards);

/**
 * @notice Emitted when a user initiates a deposit
 * @param to The address that will receive the USDN tokens
 * @param validator The address of the validator that will validate the deposit
 * @param amount The amount of assets that were deposited
 * @param timestamp The timestamp of the action
 */
event InitiatedDeposit(address indexed to, address indexed validator, uint256 amount, uint256 timestamp);

/**
 * @notice Emitted when a user validates a deposit
 * @param to The address that received the USDN tokens
 * @param validator The address of the validator that validated the deposit
 * @param amountDeposited The amount of assets that were deposited
 * @param usdnMinted The amount of USDN that was minted
 * @param timestamp The timestamp of the InitiatedDeposit action
 */
event ValidatedDeposit(
    address indexed to, address indexed validator, uint256 amountDeposited, uint256 usdnMinted, uint256 timestamp
);

/**
 * @notice Emitted when a user initiates a withdrawal
 * @param to The address that will receive the assets
 * @param validator The address of the validator that will validate the withdrawal
 * @param usdnAmount The amount of USDN that will be burned
 * @param timestamp The timestamp of the action
 */
event InitiatedWithdrawal(address indexed to, address indexed validator, uint256 usdnAmount, uint256 timestamp);

/**
 * @notice Emitted when a user validates a withdrawal
 * @param to The address that received the assets
 * @param validator The address of the validator that validated the withdrawal
 * @param amountWithdrawn The amount of assets that were withdrawn
 * @param usdnBurned The amount of USDN that was burned
 * @param timestamp The timestamp of the InitiatedWithdrawal action
 */
event ValidatedWithdrawal(
    address indexed to, address indexed validator, uint256 amountWithdrawn, uint256 usdnBurned, uint256 timestamp
);

/**
 * @notice Emitted when a user initiates the opening of a long position
 * @param owner The address that owns the position
 * @param validator The address of the validator that will validate the position
 * @param timestamp The timestamp of the action
 * @param totalExpo The initial total expo of the position (pending validation)
 * @param amount The amount of assets that were deposited as collateral
 * @param startPrice The asset price at the moment of the position creation (pending validation)
 * @param posId The unique position identifier
 */
event InitiatedOpenPosition(
    address indexed owner,
    address indexed validator,
    uint40 timestamp,
    uint128 totalExpo,
    uint128 amount,
    uint128 startPrice,
    PositionId posId
);

/**
 * @notice Emitted when a user validates the opening of a long position
 * @param owner The address that owns the position
 * @param validator The address of the validator that validated the position
 * @param totalExpo The total expo of the position
 * @param newStartPrice The asset price at the moment of the position creation (final)
 * @param posId The unique position identifier
 * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceUpdated` will be emitted too
 */
event ValidatedOpenPosition(
    address indexed owner, address indexed validator, uint128 totalExpo, uint128 newStartPrice, PositionId posId
);

/**
 * @notice Emitted when a user's position was liquidated while pending validation and we removed the pending action
 * @param validator The validator address
 * @param posId The unique position identifier
 */
event StalePendingActionRemoved(address indexed validator, PositionId posId);

/**
 * @notice Emitted when a position was moved from one tick to another
 * @param oldPosId The old position identifier
 * @param newPosId The new position identifier
 */
event LiquidationPriceUpdated(PositionId indexed oldPosId, PositionId newPosId);

/**
 * @notice Emitted when a user initiates the closing of all or part of a long position
 * @param owner The owner of this position
 * @param validator The validator for the pending action
 * @param to The address that will receive the assets
 * @param posId The unique position identifier
 * @param originalAmount The amount of collateral originally on the position
 * @param amountToClose The amount of collateral to close from the position
 * If the entirety of the position is being closed, this value equals `originalAmount`
 * @param totalExpoRemaining The total expo remaining in the position
 * If the entirety of the position is being closed, this value is zero
 */
event InitiatedClosePosition(
    address indexed owner,
    address indexed validator,
    address indexed to,
    PositionId posId,
    uint128 originalAmount,
    uint128 amountToClose,
    uint128 totalExpoRemaining
);

/**
 * @notice Emitted when a user validates the closing of a long position
 * @param validator The validator of the close action, not necessarily the position owner
 * @param to The address that received the assets
 * @param posId The unique position identifier
 * @param amountReceived The amount of assets that were sent to the user
 * @param profit The profit that the user made
 */
event ValidatedClosePosition(
    address indexed validator, address indexed to, PositionId posId, uint256 amountReceived, int256 profit
);

/**
 * @notice Emitted when a security deposit is refunded
 * @param pendingActionValidator Address of the validator
 * @param receivedBy Address of the user who received the security deposit
 * @param amount Amount of security deposit refunded
 */
event SecurityDepositRefunded(address indexed pendingActionValidator, address indexed receivedBy, uint256 amount);

/**
 * @notice Emitted when the pending protocol fee is distributed
 * @param feeCollector The collector's address
 * @param amount The amount of fee transferred
 */
event ProtocolFeeDistributed(address feeCollector, uint256 amount);

/**
 * @notice Emitted when a tick is liquidated
 * @param tick The liquidated tick
 * @param oldTickVersion The liquidated tick version
 * @param liquidationPrice The asset price at the moment of liquidation
 * @param effectiveTickPrice The effective liquidated tick price
 * @param remainingCollateral The amount of asset that was left in the tick, which was transferred to the vault if
 * positive, or was taken from the vault if negative
 */
event LiquidatedTick(
    int24 indexed tick,
    uint256 indexed oldTickVersion,
    uint256 liquidationPrice,
    uint256 effectiveTickPrice,
    int256 remainingCollateral
);

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

library UsdnProtocolActionsVaultLibrary {
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
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _initiateDeposit(
            s, msg.sender, to, validator, amount, securityDepositValue, permit2TokenBitfield, currentPriceData
        );

        if (success_) {
            unchecked {
                amountToRefund += actionsLongLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsLongLib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        actionsLongLib._checkPendingFee(s);
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
            actionsLongLib._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_) {
            unchecked {
                amountToRefund += actionsLongLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsLongLib._refundExcessEther(0, amountToRefund, balanceBefore);
        actionsLongLib._checkPendingFee(s);
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
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) =
            _initiateWithdrawal(s, msg.sender, to, validator, usdnShares, securityDepositValue, currentPriceData);

        if (success_) {
            unchecked {
                amountToRefund += actionsLongLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsLongLib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        actionsLongLib._checkPendingFee(s);
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
            actionsLongLib._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_) {
            unchecked {
                amountToRefund += actionsLongLib._executePendingActionOrRevert(s, previousActionsData);
            }
        }

        actionsLongLib._refundExcessEther(0, amountToRefund, balanceBefore);
        actionsLongLib._checkPendingFee(s);
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo();
        }

        int256 newVaultExpo = s._balanceVault.toInt256().safeAdd(s._pendingBalanceVault).safeAdd(int256(depositValue));

        int256 imbalanceBps =
            newVaultExpo.safeSub(currentLongExpo).safeMul(int256(s.BPS_DIVISOR)).safeDiv(currentLongExpo);

        if (imbalanceBps >= depositExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = (totalExpo - s._balanceLong).toInt256().safeSub(newVaultExpo).safeMul(
            int256(s.BPS_DIVISOR)
        ).safeDiv(newVaultExpo);

        if (imbalanceBps >= withdrawalExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
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
        PriceInfo memory currentPrice = actionsLongLib._getOraclePrice(
            s,
            ProtocolAction.InitiateDeposit,
            block.timestamp,
            actionsLongLib._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
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
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
        }
        uint32 burnRatio = s._sdexBurnOnDepositRatio;
        data_.sdexToBurn = vaultLib._calcSdexToBurn(s, usdnToMintEstimated, burnRatio);
        // we want to at least burn 1 wei of SDEX if SDEX burning is enabled
        if (burnRatio != 0 && data_.sdexToBurn == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (amount == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
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

        emit InitiatedDeposit(to, validator, amount, block.timestamp);
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
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

        PriceInfo memory currentPrice = actionsLongLib._getOraclePrice(
            s,
            ProtocolAction.ValidateDeposit,
            deposit.timestamp,
            actionsLongLib._calcActionId(deposit.validator, deposit.timestamp),
            priceData
        );

        // adjust balances
        (, bool isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
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
        emit ValidatedDeposit(deposit.to, deposit.validator, deposit.amount, mintedTokens, deposit.timestamp);
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
        PriceInfo memory currentPrice = actionsLongLib._getOraclePrice(
            s,
            ProtocolAction.InitiateWithdrawal,
            block.timestamp,
            actionsLongLib._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (usdnShares == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
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
        emit InitiatedWithdrawal(to, validator, s._usdn.convertToTokens(usdnShares), block.timestamp);
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
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
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

        PriceInfo memory currentPrice = actionsLongLib._getOraclePrice(
            s,
            ProtocolAction.ValidateWithdrawal,
            withdrawal.timestamp,
            actionsLongLib._calcActionId(withdrawal.validator, withdrawal.timestamp),
            priceData
        );

        (, bool isLiquidationPending) = longLib._applyPnlAndFundingAndLiquidate(
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

        uint256 available;
        {
            // apply fees on price
            uint128 withdrawalPriceWithFees =
                (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

            // we calculate the available balance of the vault side, either considering the asset price at the time of
            // the
            // initiate action, or the current price provided for validation. We will use the lower of the two amounts
            // to
            // redeem the underlying asset share
            uint256 available1 = withdrawal.balanceVault;
            uint256 available2 = vaultLib._vaultAssetAvailable(
                withdrawal.totalExpo,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                withdrawalPriceWithFees,
                withdrawal.assetPrice
            ).toUint256();
            if (available1 <= available2) {
                available = available1;
            } else {
                available = available2;
            }
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

        emit ValidatedWithdrawal(
            withdrawal.to, withdrawal.validator, assetToTransfer, s._usdn.convertToTokens(shares), withdrawal.timestamp
        );
    }
}
