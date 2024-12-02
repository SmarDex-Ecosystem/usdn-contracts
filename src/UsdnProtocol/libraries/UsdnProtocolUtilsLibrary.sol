// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IFeeCollectorCallback } from "../../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IPaymentCallback } from "../../interfaces/UsdnProtocol/IPaymentCallback.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";

/**
 * @title USDN Protocol Utilities
 * @notice A library of utility functions for the `USDN protocol`. This library is not intended to be deployed as an
 * external library.
 * @dev All functions in this library must be marked as "internal".
 */
library UsdnProtocolUtilsLibrary {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using HugeUint for HugeUint.Uint512;
    using SafeCast for uint256;
    using SafeTransferLib for address;
    using SignedMath for int256;

    /**
     * @notice Constant representing the storage slot for the protocol main storage.
     * @dev Calculated as:
     *  `keccak256(abi.encode(uint256(keccak256("UsdnProtocol.storage.main")) - 1)) & ~bytes32(uint256(0xff))`
     */
    bytes32 private constant STORAGE_MAIN = 0xd143a936a6a372725e12535db83a2cfabcb3715dfd88bc350da3399604dc9700;

    /**
     * @notice Get the main storage pointer.
     * @return s_ The pointer to the main storage structure.
     */
    function _getMainStorage() internal pure returns (Types.Storage storage s_) {
        assembly {
            s_.slot := STORAGE_MAIN
        }
    }

    /**
     * @notice Refund excess Ether to prevent unintended locking of funds.
     * @param securityDepositValue The security deposit for the current action (zero for validation actions).
     * @param amountToRefund The amount to refund to the user: the security deposit when executing an action for another
     * user, and/or the initialization security deposit in the case of a validation action.
     * @param balanceBefore The contract's balance before the action.
     */
    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) internal {
        uint256 positive = amountToRefund + address(this).balance + msg.value;
        uint256 negative = balanceBefore + securityDepositValue;

        if (negative > positive) {
            revert IUsdnProtocolErrors.UsdnProtocolUnexpectedBalance();
        }

        uint256 amount;
        unchecked {
            // we know that positive >= negative, so this subtraction is safe
            amount = positive - negative;
        }

        _refundEther(amount, payable(msg.sender));
    }

    /**
     * @notice Refund Ether to a specified address.
     * @param amount The amount of Ether to refund.
     * @param to The address receiving the refund.
     */
    function _refundEther(uint256 amount, address payable to) internal {
        if (to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (amount != 0) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = to.call{ value: amount }("");
            if (!success) {
                revert IUsdnProtocolErrors.UsdnProtocolEtherRefundFailed();
            }
        }
    }

    /**
     * @notice Distribute the protocol fee to the fee collector if the pending amount exceeds the threshold.
     * @dev Attempts to invoke the `feeCollectorCallback` function on the fee collector if supported.
     */
    function _checkPendingFee() internal {
        Types.Storage storage s = _getMainStorage();

        uint256 pendingFee = s._pendingProtocolFee;
        if (pendingFee >= s._feeThreshold) {
            address feeCollector = s._feeCollector;

            emit IUsdnProtocolEvents.ProtocolFeeDistributed(feeCollector, pendingFee);
            s._pendingProtocolFee = 0;
            address(s._asset).safeTransfer(feeCollector, pendingFee);

            if (ERC165Checker.supportsInterface(feeCollector, type(IFeeCollectorCallback).interfaceId)) {
                IFeeCollectorCallback(feeCollector).feeCollectorCallback(pendingFee);
            }
        }
    }

    /**
     * @notice Get and validate the oracle price for a specified action and timestamp.
     * @param action The protocol action being performed.
     * @param timestamp The timestamp for which the price is queried.
     * @param actionId The unique identifier of the action.
     * @param priceData The encoded oracle price data.
     * @return price_ The validated price information.
     */
    function _getOraclePrice(Types.ProtocolAction action, uint256 timestamp, bytes32 actionId, bytes calldata priceData)
        internal
        returns (PriceInfo memory price_)
    {
        Types.Storage storage s = _getMainStorage();

        uint256 validationCost = s._oracleMiddleware.validationCost(priceData, action);
        if (address(this).balance < validationCost) {
            revert IUsdnProtocolErrors.UsdnProtocolInsufficientOracleFee();
        }
        // slither-disable-next-line arbitrary-send-eth
        price_ = s._oracleMiddleware.parseAndValidatePrice{ value: validationCost }(
            actionId, uint128(timestamp), action, priceData
        );
    }

    /**
     * @notice Clear the pending action of a user.
     * @param user The user's address.
     * @param rawIndex The `rawIndex` of the pending action in the queue.
     */
    function _clearPendingAction(address user, uint128 rawIndex) internal {
        Types.Storage storage s = _getMainStorage();

        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Calculate the long balance, including unreflected PnL (excluding funding).
     * @dev This function uses the latest total exposure, balance, and stored price as reference values. It adjusts the
     * balance by adding the PnL resulting from the price change.
     * @param currentPrice The current price of the asset.
     * @return available_ The updated balance on the long side.
     */
    function _longAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        Types.Storage storage s = _getMainStorage();

        available_ = _longAssetAvailable(s._totalExpo, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Calculate the hash and version for a given tick number.
     * @param tick The tick number.
     * @return hash_ The hash of the tick.
     * @return version_ The version of the tick.
     */
    function _tickHash(int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        Types.Storage storage s = _getMainStorage();

        version_ = s._tickVersion[tick];
        hash_ = _tickHash(tick, version_);
    }

    /**
     * @notice Convert a signed tick to an unsigned index into the Bitmap based on the storage tick spacing.
     * @param tick The tick number, a multiple of the tick spacing.
     * @return index_ The index into the Bitmap.
     */
    function _calcBitmapIndexFromTick(int24 tick) internal view returns (uint256 index_) {
        Types.Storage storage s = _getMainStorage();

        index_ = _calcBitmapIndexFromTick(tick, s._tickSpacing);
    }

    /**
     * @notice Get the effective price, accounting for funding, for a given tick.
     * @param tick The tick number.
     * @return price_ The effective price for the tick.
     */
    function _getEffectivePriceForTick(int24 tick) internal view returns (uint128 price_) {
        Types.Storage storage s = _getMainStorage();

        price_ =
            _getEffectivePriceForTick(tick, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator);
    }

    /**
     * @notice Generate a hash based on the tick and a version.
     * @param tick The tick number.
     * @param version The tick version.
     * @return The hash value.
     */
    function _tickHash(int24 tick, uint256 version) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    /**
     * @notice Convert a `uint128` to an `int256`.
     * @param x The `uint128` value to convert.
     * @return The resulting `int256` value.
     */
    function _toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Optimized position value calculation when `posTotalExpo` is known to be a uint128 and `currentPrice`
     * is guaranteed to be above `liqPriceWithoutPenalty`.
     * @param posTotalExpo The total exposure of the position.
     * @param currentPrice The current asset price.
     * @param liqPriceWithoutPenalty The liquidation price without penalty.
     * @return posValue_ The calculated position value.
     */
    function _positionValueOptimized(uint128 posTotalExpo, uint128 currentPrice, uint128 liqPriceWithoutPenalty)
        internal
        pure
        returns (uint256 posValue_)
    {
        // posValue_ = uint256(posTotalExpo) * (currentPrice - liqPriceWithoutPenalty) / currentPrice;
        posValue_ = currentPrice - liqPriceWithoutPenalty;
        unchecked {
            // the multiplication cannot overflow because both operands are uint128
            posValue_ *= posTotalExpo;
        }
        posValue_ /= currentPrice;
    }

    /**
     * @notice Calculate the tick number without considering the liquidation penalty.
     * @param tick The tick number that holds the position.
     * @param liquidationPenalty The liquidation penalty, measured in ticks.
     * @return tick_ The tick number adjusted to exclude the liquidation penalty.
     */
    function _calcTickWithoutPenalty(int24 tick, uint24 liquidationPenalty) internal pure returns (int24 tick_) {
        tick_ = tick - int24(liquidationPenalty);
    }

    /**
     * @notice Compute the theoretical liquidation price of a position using its entry price and leverage.
     * @param startPrice The entry price of the position.
     * @param leverage The leverage of the position.
     * @return price_ The computed liquidation price.
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** Constants.LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    /**
     * @notice Compute the leverage of a position using its entry price and liquidation price.
     * @dev The calculation does not take into account the liquidation penalty.
     * @param startPrice The entry price of the position.
     * @param liquidationPrice The price at which the position would be liquidated.
     * @return leverage_ The computed leverage value.
     */
    function _getLeverage(uint128 startPrice, uint128 liquidationPrice) internal pure returns (uint256 leverage_) {
        if (startPrice <= liquidationPrice) {
            // this situation is not allowed (newly open position must be solvent)
            // also, the calculation below would underflow
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        leverage_ = (10 ** Constants.LEVERAGE_DECIMALS * uint256(startPrice)) / (startPrice - liquidationPrice);
    }

    /**
     * @notice Convert a `LongPendingAction` to a `PendingAction`.
     * @param action The long pending action.
     * @return pendingAction_ The converted untyped pending action.
     */
    function _convertLongPendingAction(Types.LongPendingAction memory action)
        internal
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `WithdrawalPendingAction` to a `PendingAction`.
     * @param action The withdrawal pending action.
     * @return pendingAction_ The converted untyped pending action.
     */
    function _convertWithdrawalPendingAction(Types.WithdrawalPendingAction memory action)
        internal
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `DepositPendingAction` to a `PendingAction`.
     * @param action The deposit pending action.
     * @return pendingAction_ The converted untyped pending action.
     */
    function _convertDepositPendingAction(Types.DepositPendingAction memory action)
        internal
        pure
        returns (Types.PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `LongPendingAction`.
     * @param action The untyped pending action.
     * @return longAction_ The converted long pending action.
     */
    function _toLongPendingAction(Types.PendingAction memory action)
        internal
        pure
        returns (Types.LongPendingAction memory longAction_)
    {
        assembly {
            longAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `DepositPendingAction`.
     * @param action The untyped pending action.
     * @return vaultAction_ The converted deposit pending action.
     */
    function _toDepositPendingAction(Types.PendingAction memory action)
        internal
        pure
        returns (Types.DepositPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @notice Convert a `PendingAction` to a `WithdrawalPendingAction`.
     * @param action The untyped pending action.
     * @return vaultAction_ The converted withdrawal pending action.
     */
    function _toWithdrawalPendingAction(Types.PendingAction memory action)
        internal
        pure
        returns (Types.WithdrawalPendingAction memory vaultAction_)
    {
        assembly {
            vaultAction_ := action
        }
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap, based on the specified tick spacing.
     * @param tick The signed tick, which must be a multiple of `tickSpacing`.
     * @param tickSpacing The tick spacing to use.
     * @return index_ The corresponding index into the Bitmap.
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) internal pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `WithdrawalPendingAction`.
     * @param sharesLSB The lower 24 bits of the USDN shares.
     * @param sharesMSB The higher bits of the USDN shares.
     * @return usdnShares_ The amount of USDN shares.
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        internal
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }

    /**
     * @notice Compute the updated balance of the long side, considering unreflected PnL (excluding funding).
     * @param totalExpo The total exposure of the long side.
     * @param balanceLong The previous balance of the long side.
     * @param newPrice The updated price of the asset.
     * @param oldPrice The previous price used to calculate the prior balance.
     * @return available_ The updated balance of the long side.
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 available_)
    {
        int256 priceDiff = _toInt256(newPrice) - _toInt256(oldPrice);
        uint256 tradingExpo = totalExpo - balanceLong;

        int256 pnl = tradingExpo.toInt256().safeMul(priceDiff).safeDiv(_toInt256(newPrice));

        available_ = balanceLong.toInt256().safeAdd(pnl);
    }

    /**
     * @notice Calculate the imbalance between the vault and long sides.
     * @dev A positive value indicates the long trading exposure is smaller than the vault's. If the trading exposure is
     * equal to 0, the imbalance is infinite and int256.max is returned.
     * @param vaultBalance The balance of the vault.
     * @param longBalance The balance of the long side.
     * @param totalExpo The total exposure of the long side.
     * @return imbalanceBps_ The imbalance, expressed in basis points.
     */
    function _calcImbalanceCloseBps(int256 vaultBalance, int256 longBalance, uint256 totalExpo)
        internal
        pure
        returns (int256 imbalanceBps_)
    {
        int256 tradingExpo = totalExpo.toInt256().safeSub(longBalance);
        if (tradingExpo == 0) {
            return type(int256).max;
        }

        // imbalanceBps_ = (vaultBalance - (totalExpo - longBalance)) * (totalExpo - longBalance)
        imbalanceBps_ = (vaultBalance.safeSub(tradingExpo)).safeMul(int256(Constants.BPS_DIVISOR)).safeDiv(tradingExpo);
    }

    /**
     * @notice Calculate the total exposure of a position.
     * @dev Reverts if `startPrice <= liquidationPrice`.
     * @param amount The amount of assets used as collateral.
     * @param startPrice The asset price when the position was created.
     * @param liquidationPrice The liquidation price of the position.
     * @return totalExpo_ The total exposure of the position.
     */
    function _calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        internal
        pure
        returns (uint128 totalExpo_)
    {
        if (startPrice <= liquidationPrice) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLiquidationPrice(liquidationPrice, startPrice);
        }

        totalExpo_ = FixedPointMathLib.fullMulDiv(amount, startPrice, startPrice - liquidationPrice).toUint128();
    }

    /**
     * @notice Compute the value of a position based on its liquidation price and the current asset price.
     * @param positionTotalExpo The total exposure of the position.
     * @param currentPrice The current price of the asset.
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty.
     * @return value_ The position's value. Negative values indicate bad debt.
     */
    function _positionValue(uint128 positionTotalExpo, uint128 currentPrice, uint128 liqPriceWithoutPenalty)
        internal
        pure
        returns (int256 value_)
    {
        if (currentPrice < liqPriceWithoutPenalty) {
            value_ = -FixedPointMathLib.fullMulDiv(positionTotalExpo, liqPriceWithoutPenalty - currentPrice, currentPrice)
                .toInt256();
        } else {
            value_ = FixedPointMathLib.fullMulDiv(
                positionTotalExpo, currentPrice - liqPriceWithoutPenalty, currentPrice
            ).toInt256();
        }
    }

    /**
     * @notice Calculate a fixed-precision representation of the liquidation price multiplier.
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposure of the long side.
     * @param accumulator The liquidation multiplier accumulator.
     * @return multiplier_ The liquidation price multiplier.
     */
    function _calcFixedPrecisionMultiplier(
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (uint256 multiplier_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS;
        }
        // M = assetPrice * longTradingExpo / accumulator
        // with longTradingExpo = totalExpo - balanceLong
        HugeUint.Uint512 memory numerator =
            HugeUint.mul(10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS, assetPrice * longTradingExpo);
        multiplier_ = numerator.div(accumulator);
    }

    /**
     * @notice Variant of `_adjustPrice` when a fixed precision representation of the liquidation multiplier is known.
     * @param unadjustedPrice The unadjusted price for the tick.
     * @param liqMultiplier The liquidation price multiplier.
     * @return price_ The adjusted price for the tick.
     */
    function _adjustPrice(uint256 unadjustedPrice, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(
            unadjustedPrice, liqMultiplier, 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
    }

    /**
     * @notice Calculate the amount of USDN shares to mint for a given amount of assets.
     * @param amount The amount of assets to be converted into USDN.
     * @param vaultBalance The current balance of the vault.
     * @param usdnTotalShares The total supply of USDN shares.
     * @return toMint_ The amount of USDN shares to mint.
     */
    function _calcMintUsdnShares(uint256 amount, uint256 vaultBalance, uint256 usdnTotalShares)
        internal
        pure
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }
        // the amount of USDN shares to mint is calculated as follows:
        // amountUsdn = amountAsset * priceAsset / priceUsdn,
        // but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
        // amountUsdn = amountAsset * totalSupply / vaultBalance, and
        // sharesUsdn = amountAsset * totalShares / vaultBalance
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalShares, vaultBalance);
    }

    /**
     * @notice Calculate the amount of SDEX tokens to burn when minting USDN tokens.
     * @dev The result is rounded up to ensure at least 1 wei of SDEX is burned.
     * @param usdnAmount The amount of USDN to be minted.
     * @param sdexBurnRatio The ratio of SDEX burned per minted USDN.
     * @return sdexToBurn_ The amount of SDEX tokens to burn.
     */
    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) internal pure returns (uint256 sdexToBurn_) {
        sdexToBurn_ = FixedPointMathLib.fullMulDivUp(usdnAmount, sdexBurnRatio, Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR);
    }

    /**
     * @notice Calculate a unique identifier for a pending action.
     * @dev This identifier can be used by the oracle middleware to link an `Initiate` call with the corresponding
     * `Validate` call.
     * @param validator The address of the validator.
     * @param initiateTimestamp The timestamp of the `Initiate` action.
     * @return actionId_ The unique action ID.
     */
    function _calcActionId(address validator, uint128 initiateTimestamp) internal pure returns (bytes32 actionId_) {
        actionId_ = keccak256(abi.encodePacked(validator, initiateTimestamp));
    }

    /**
     * @notice Calculate the amount of assets received when burning USDN shares, accounting for fees.
     * @param usdnShares The amount of USDN shares to burn.
     * @param vaultAvailableBalance The available amount of assets in the vault.
     * @param usdnSharesTotalSupply The total supply of USDN shares.
     * @param feeBps The fee in basis points.
     * @return expectedAssetsAmount_ The expected amount of assets to be received after deducting fees.
     */
    function _calcAmountToWithdraw(
        uint256 usdnShares,
        uint256 vaultAvailableBalance,
        uint256 usdnSharesTotalSupply,
        uint256 feeBps
    ) internal pure returns (uint256 expectedAssetsAmount_) {
        // amount = amountUsdn * usdnPrice / assetPrice
        //        = usdnShares * vaultAvailableBalance / usdnSharesTotalSupply
        //
        // amountAfterFees = amount - (amount * feeBps / BPS_DIVISOR)
        //                 = usdnShares * (vaultAvailableBalance * (BPS_DIVISOR - feeBps))
        //                              / (usdnSharesTotalSupply * BPS_DIVISOR)
        // Note: the second division is moved out of the fullMulDiv to avoid an overflow in the denominator
        expectedAssetsAmount_ = FixedPointMathLib.fullMulDiv(
            usdnShares, vaultAvailableBalance * (Constants.BPS_DIVISOR - feeBps), usdnSharesTotalSupply
        ) / Constants.BPS_DIVISOR;
    }

    /**
     * @notice Compute the available balance in the vault for a given price, excluding funding effects.
     * @param totalExpo The total long exposure.
     * @param balanceVault The previous balance of the vault.
     * @param balanceLong The previous balance of the long side.
     * @param newPrice The updated price.
     * @param oldPrice The price used when the previous balances were calculated.
     * @return available_ The available balance in the vault.
     */
    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) internal pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = _longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    /**
     * @notice Adjust the tick price by accounting for the effects of funding.
     * @param unadjustedPrice The tick's unadjusted price.
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposure of the long side.
     * @param accumulator The liquidation multiplier accumulator.
     * @return price_ The adjusted tick price.
     */
    function _adjustPrice(
        uint256 unadjustedPrice,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (uint128 price_) {
        if (accumulator.hi == 0 && accumulator.lo == 0) {
            // no position in long, we assume a liquidation multiplier of 1.0
            return unadjustedPrice.toUint128();
        }

        // price = unadjustedPrice * M
        // with M = assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator = HugeUint.mul(unadjustedPrice, assetPrice * longTradingExpo);
        price_ = numerator.div(accumulator).toUint128();
    }

    /**
     * @notice Invoke a callback on the `msg.sender` to transfer assets and verifies that they were received.
     * @param token The ERC-20 token to transfer.
     * @param amount The amount of tokens to transfer.
     * @param to The recipient's address.
     */
    function _transferCallback(IERC20Metadata token, uint256 amount, address to) internal {
        uint256 balanceBefore = token.balanceOf(to);
        IPaymentCallback(msg.sender).transferCallback(token, amount, to);
        uint256 balanceAfter = token.balanceOf(to);
        if (balanceAfter != balanceBefore + amount) {
            revert IUsdnProtocolErrors.UsdnProtocolPaymentCallbackFailed();
        }
    }

    /**
     * @notice Invoke a callback on the `msg.sender` to transfer USDN shares and verifies that they were received.
     * @param usdn The address of the USDN token contract.
     * @param shares The amount of USDN shares to transfer.
     */
    function _usdnTransferCallback(IUsdn usdn, uint256 shares) internal {
        uint256 balanceBefore = usdn.sharesOf(address(this));
        IPaymentCallback(msg.sender).usdnTransferCallback(usdn, shares);
        uint256 balanceAfter = usdn.sharesOf(address(this));
        if (balanceAfter != balanceBefore + shares) {
            revert IUsdnProtocolErrors.UsdnProtocolPaymentCallbackFailed();
        }
    }

    /**
     * @notice Calculate the effective price for a tick, adjusted for funding effects.
     * @param tick The tick number.
     * @param assetPrice The current price of the asset.
     * @param longTradingExpo The trading exposure of the long side (total exposure - balance long).
     * @param accumulator The liquidation multiplier accumulator.
     * @return price_ The adjusted price for the tick.
     */
    function _getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }

    /**
     * @notice Variant of `_getEffectivePriceForTick` when a fixed precision representation of the liquidation
     * multiplier is known.
     * @param tick The tick number.
     * @param liqMultiplier The liquidation price multiplier.
     * @return price_ The adjusted price for the tick.
     */
    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), liqMultiplier);
    }
}
