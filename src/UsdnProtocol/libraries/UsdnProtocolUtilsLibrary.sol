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
 * @title USDN Protocol Utils
 * @notice This library contains utility functions for the USDN protocol, and will not be deployed as an external lib
 * @dev All functions should be marked as "internal"
 */
library UsdnProtocolUtilsLibrary {
    using DoubleEndedQueue for DoubleEndedQueue.Deque;
    using HugeUint for HugeUint.Uint512;
    using SafeCast for uint256;
    using SafeTransferLib for address;
    using SignedMath for int256;

    /**
     * @notice The slot in which the main storage is stored
     * @dev keccak256(abi.encode(uint256(keccak256("UsdnProtocol.storage.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant STORAGE_MAIN = 0xd143a936a6a372725e12535db83a2cfabcb3715dfd88bc350da3399604dc9700;

    /**
     * @notice Get the main storage slot pointer
     * @return s_ The main storage slot pointer
     */
    function _getMainStorage() internal pure returns (Types.Storage storage s_) {
        assembly {
            s_.slot := STORAGE_MAIN
        }
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
     * @notice Refunds an amount of ether to the given address
     * @param amount The amount of ether to refund
     * @param to The address that should receive the refund
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
     * @notice Distribute the protocol fee to the fee collector if it exceeds the threshold
     * @dev This function is called after every action that changes the protocol fee balance
     * Try to call the function `feeCollectorCallback` on the fee collector if it supports the interface (non reverting
     * if it fails)
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
     * @notice Get the oracle price for the given action and timestamp then validate it
     * @param action The type of action that is being performed by the user
     * @param timestamp The timestamp at which the wanted price was recorded
     * @param actionId The unique identifier of the action
     * @param priceData The price oracle data
     * @return price_ The validated price
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
     * @notice Clear the pending action for a user
     * @param user The user's address
     * @param rawIndex The rawIndex of the pending action in the queue
     */
    function _clearPendingAction(address user, uint128 rawIndex) internal {
        Types.Storage storage s = _getMainStorage();

        s._pendingActionsQueue.clearAt(rawIndex);
        delete s._pendingActions[user];
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @dev This function uses the latest total expo, balance and stored price as the reference values, and adds the PnL
     * due to the price change to `currentPrice`
     * @param currentPrice The current price
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        Types.Storage storage s = _getMainStorage();

        available_ = _longAssetAvailable(s._totalExpo, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Function to calculate the hash and version of a given tick
     * @param tick The tick
     * @return hash_ The hash of the tick
     * @return version_ The version of the tick
     */
    function _tickHash(int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        Types.Storage storage s = _getMainStorage();

        version_ = s._tickVersion[tick];
        hash_ = tickHash(tick, version_);
    }

    /**
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the tick spacing in storage
     * @param tick The tick to convert, a multiple of the tick spacing
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick) internal view returns (uint256 index_) {
        Types.Storage storage s = _getMainStorage();

        index_ = _calcBitmapIndexFromTick(tick, s._tickSpacing);
    }

    /// @notice See {IUsdnProtocolFallback}
    function getEffectivePriceForTick(int24 tick) internal view returns (uint128 price_) {
        Types.Storage storage s = _getMainStorage();

        price_ =
            getEffectivePriceForTick(tick, s._lastPrice, s._totalExpo - s._balanceLong, s._liqMultiplierAccumulator);
    }

    /// @notice See {IUsdnProtocolFallback}
    function tickHash(int24 tick, uint256 version) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    /**
     * @notice Convert a uint128 to an int256
     * @param x The value to convert
     * @return The converted value
     */
    function toInt256(uint128 x) internal pure returns (int256) {
        return int256(uint256(x));
    }

    /**
     * @notice Optimized position value calculation when `posTotalExpo` is known to be uint128 and `currentPrice` is
     * known to be above `liqPriceWithoutPenalty`
     * @param posTotalExpo The total expo of the position
     * @param currentPrice The current asset price
     * @param liqPriceWithoutPenalty The liquidation price without penalty
     * @return posValue_ The value of the position, which must be positive
     */
    function positionValue(uint128 posTotalExpo, uint128 currentPrice, uint128 liqPriceWithoutPenalty)
        internal
        pure
        returns (uint256 posValue_)
    {
        // the multiplication cannot overflow because both operands are uint128
        posValue_ = uint256(posTotalExpo) * (currentPrice - liqPriceWithoutPenalty) / currentPrice;
    }

    /**
     * @notice Calculate the tick without the liquidation penalty
     * @param tick The tick that holds the position
     * @param liquidationPenalty The liquidation penalty of the tick, in number of ticks
     * @return tick_ The tick corresponding to the liquidation price without penalty
     */
    function calcTickWithoutPenalty(int24 tick, uint24 liquidationPenalty) internal pure returns (int24 tick_) {
        tick_ = tick - int24(liquidationPenalty);
    }

    /**
     * @notice Calculate the theoretical liquidation price of a position knowing its start price and leverage
     * @param startPrice Entry price of the position
     * @param leverage Leverage of the position
     * @return price_ The liquidation price of the position
     */
    function _getLiquidationPrice(uint128 startPrice, uint128 leverage) internal pure returns (uint128 price_) {
        price_ = (startPrice - ((uint256(10) ** Constants.LEVERAGE_DECIMALS * startPrice) / leverage)).toUint128();
    }

    /**
     * @notice Calculate the leverage of a position, knowing its start price and liquidation price
     * @dev This does not take into account the liquidation penalty
     * @param startPrice Entry price of the position
     * @param liquidationPrice Liquidation price of the position
     * @return leverage_ The leverage of the position
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
     * @notice Convert a `Types.LongPendingAction` to a `Types.PendingAction`
     * @param action A long pending action
     * @return pendingAction_ The converted untyped pending action
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
     * @notice Convert a `Types.WithdrawalPendingAction` to a `Types.PendingAction`
     * @param action A withdrawal pending action
     * @return pendingAction_ The converted untyped pending action
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
     * @notice Convert a `Types.DepositPendingAction` to a `Types.PendingAction`
     * @param action A deposit pending action
     * @return pendingAction_ The converted untyped pending action
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
     * @notice Convert a `Types.PendingAction` to a `Types.LongPendingAction`
     * @param action An untyped pending action
     * @return longAction_ The converted long pending action
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
     * @notice Convert a `Types.PendingAction` to a `Types.DepositPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted deposit pending action
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
     * @notice Convert a `Types.PendingAction` to a `Types.WithdrawalPendingAction`
     * @param action An untyped pending action
     * @return vaultAction_ The converted withdrawal pending action
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
     * @dev Convert a signed tick to an unsigned index into the Bitmap using the provided tick spacing
     * @param tick The tick to convert, a multiple of `tickSpacing`
     * @param tickSpacing The tick spacing to use
     * @return index_ The index into the Bitmap
     */
    function _calcBitmapIndexFromTick(int24 tick, int24 tickSpacing) internal pure returns (uint256 index_) {
        index_ = uint256( // cast is safe as the min tick is always above TickMath.MIN_TICK
            (int256(tick) - TickMath.MIN_TICK) // shift into positive
                / tickSpacing
        );
    }

    /**
     * @notice Merge the two parts of the withdrawal amount (USDN shares) stored in the `Types.WithdrawalPendingAction`
     * @param sharesLSB The lower 24 bits of the USDN shares
     * @param sharesMSB The higher bits of the USDN shares
     * @return usdnShares_ The amount of USDN shares
     */
    function _mergeWithdrawalAmountParts(uint24 sharesLSB, uint128 sharesMSB)
        internal
        pure
        returns (uint256 usdnShares_)
    {
        usdnShares_ = sharesLSB | uint256(sharesMSB) << 24;
    }

    /**
     * @notice Calculate the long balance taking into account unreflected PnL (but not funding)
     * @param totalExpo The total exposure of the long side
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balance was updated
     * @return available_ The available balance on the long side
     */
    function _longAssetAvailable(uint256 totalExpo, uint256 balanceLong, uint128 newPrice, uint128 oldPrice)
        internal
        pure
        returns (int256 available_)
    {
        int256 priceDiff = toInt256(newPrice) - toInt256(oldPrice);
        uint256 tradingExpo = totalExpo - balanceLong;

        int256 pnl = tradingExpo.toInt256().safeMul(priceDiff).safeDiv(toInt256(newPrice));

        available_ = balanceLong.toInt256().safeAdd(pnl);
    }

    /**
     * @notice Calculates the current imbalance between the vault and long sides
     * @dev If the value is positive, the long trading expo is smaller than the vault trading expo
     * If the trading expo is equal to 0, the imbalance is infinite and int256.max is returned
     * @param vaultBalance The balance of the vault
     * @param longBalance The balance of the long side
     * @param totalExpo The total expo of the long side
     * @return imbalanceBps_ The imbalance in basis points
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

        // imbalanceBps_ = (vaultBalance - (totalExpo - longBalance)) *s. (totalExpo - longBalance);
        imbalanceBps_ = (vaultBalance.safeSub(tradingExpo)).safeMul(int256(Constants.BPS_DIVISOR)).safeDiv(tradingExpo);
    }

    /**
     * @notice Calculate the total exposure of a position
     * @dev Reverts when startPrice <= liquidationPrice
     * @param amount The amount of asset used as collateral
     * @param startPrice The price of the asset when the position was created
     * @param liquidationPrice The liquidation price of the position
     * @return totalExpo_ The total exposure of a position
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
     * @notice Calculate the value of a position, knowing its liquidation price and the current asset price
     * @param currentPrice The current price of the asset
     * @param liqPriceWithoutPenalty The liquidation price of the position without the liquidation penalty
     * @param positionTotalExpo The total expo of the position
     * @return value_ The value of the position. If the current price is smaller than the liquidation price without
     * penalty, then the position value is negative (bad debt)
     */
    function _positionValue(uint128 currentPrice, uint128 liqPriceWithoutPenalty, uint128 positionTotalExpo)
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
     * @notice Calculate a fixed-precision representation of the liquidation price multiplier
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return multiplier_ The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
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
        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator =
            HugeUint.mul(10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS, assetPrice * longTradingExpo);
        multiplier_ = numerator.div(accumulator);
    }

    /**
     * @notice Variant of `getEffectivePriceForTick` when a fixed precision representation of the liquidation multiplier
     * is known
     * @param tick The tick number
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _getEffectivePriceForTick(int24 tick, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), liqMultiplier);
    }

    /**
     * @notice Variant of _adjustPrice when a fixed precision representation of the liquidation multiplier is known
     * @param unadjustedPrice The unadjusted price for the tick
     * @param liqMultiplier The liquidation price multiplier, with LIQUIDATION_MULTIPLIER_DECIMALS decimals
     * @return price_ The adjusted price for the tick
     */
    function _adjustPrice(uint256 unadjustedPrice, uint256 liqMultiplier) internal pure returns (uint128 price_) {
        // price = unadjustedPrice * M
        price_ = FixedPointMathLib.fullMulDiv(
            unadjustedPrice, liqMultiplier, 10 ** Constants.LIQUIDATION_MULTIPLIER_DECIMALS
        ).toUint128();
    }

    /**
     * @notice Calculates the amount of USDN shares to mint for a given amount of asset
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault
     * @param usdnTotalShares The total supply of USDN
     * @return toMint_ The amount of USDN to mint
     * @dev The amount of USDN shares to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance, and
     * sharesUsdn = amountAsset * totalShares / vaultBalance
     */
    function _calcMintUsdnShares(uint256 amount, uint256 vaultBalance, uint256 usdnTotalShares)
        internal
        pure
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }
        // we simply mint a proportional number of shares corresponding to the new assets deposited into the vault
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalShares, vaultBalance);
    }

    /**
     * @notice Calculate the amount of SDEX to burn when minting USDN tokens (rounding up)
     * @dev We round up to make sure we burn at least 1 wei SDEX during the minting process
     * @param usdnAmount The amount of USDN to be minted
     * @param sdexBurnRatio The ratio of SDEX to burn for each minted USDN
     * @return sdexToBurn_ The amount of SDEX to burn for the given USDN amount
     */
    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) internal pure returns (uint256 sdexToBurn_) {
        sdexToBurn_ = FixedPointMathLib.fullMulDivUp(usdnAmount, sdexBurnRatio, Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR);
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

    /**
     * @notice Calculate the amount of assets received when burning USDN shares (after fees)
     * @param usdnShares The amount of USDN shares to burn
     * @param vaultAvailableBalance The available amount of assets in the vault
     * @param usdnSharesTotalSupply The total supply of USDN shares
     * @param feeBps The fee in basis points
     * @return expectedAssetsAmount_ The expected amount of assets to be received, after fees
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
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param totalExpo The total expo
     * @param balanceVault The (old) balance of the vault
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balances were updated
     * @return available_ The available balance in the vault side
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
     * @notice Knowing the unadjusted price for a tick, get the adjusted price taking into account the effects of the
     * funding
     * @param unadjustedPrice The unadjusted price for the tick
     * @param assetPrice The current price of the asset
     * @param longTradingExpo The trading expo of the long side (total expo - balance long)
     * @param accumulator The liquidation multiplier accumulator
     * @return price_ The adjusted price for the tick
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

        // M = assetPrice * (totalExpo - balanceLong) / accumulator
        // price = unadjustedPrice * M
        // price = unadjustedPrice * assetPrice * (totalExpo - balanceLong) / accumulator
        HugeUint.Uint512 memory numerator = HugeUint.mul(unadjustedPrice, assetPrice * longTradingExpo);
        price_ = numerator.div(accumulator).toUint128();
    }

    /**
     * @notice Call back the msg.sender to transfer assets and check that they were received
     * @param token The token to transfer
     * @param amount The amount to transfer
     * @param to The address of the recipient
     */
    function transferCallback(IERC20Metadata token, uint256 amount, address to) internal {
        uint256 balanceBefore = token.balanceOf(to);
        IPaymentCallback(msg.sender).transferCallback(token, amount, to);
        uint256 balanceAfter = token.balanceOf(to);
        if (balanceAfter != balanceBefore + amount) {
            revert IUsdnProtocolErrors.UsdnProtocolPaymentCallbackFailed();
        }
    }

    /**
     * @notice Call back the msg.sender to transfer USDN shares and check that they were received
     * @param usdn The USDN token address
     * @param shares The amount of shares to transfer
     */
    function usdnTransferCallback(IUsdn usdn, uint256 shares) internal {
        uint256 balanceBefore = usdn.sharesOf(address(this));
        IPaymentCallback(msg.sender).usdnTransferCallback(usdn, shares);
        uint256 balanceAfter = usdn.sharesOf(address(this));
        if (balanceAfter != balanceBefore + shares) {
            revert IUsdnProtocolErrors.UsdnProtocolPaymentCallbackFailed();
        }
    }

    /// @notice See {IUsdnProtocolFallback}
    function getEffectivePriceForTick(
        int24 tick,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator
    ) internal pure returns (uint128 price_) {
        price_ = _adjustPrice(TickMath.getPriceAtTick(tick), assetPrice, longTradingExpo, accumulator);
    }
}
