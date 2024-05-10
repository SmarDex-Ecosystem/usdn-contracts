// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import {
    Position,
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    LiquidationsEffects,
    PreviousActionsData,
    PositionId,
    TickData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolCommon } from "src/UsdnProtocol/UsdnProtocolCommon.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

abstract contract UsdnProtocolVaultProxy is UsdnProtocolCommon, InitializableReentrancyGuard {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    /**
     * @dev Structure to hold the transient data during `_initiateWithdrawal`
     * @param pendingActionPrice The adjusted price with position fees applied
     * @param totalExpo The current total expo
     * @param balanceLong The current long balance
     * @param balanceVault The vault balance, adjusted according to the pendingActionPrice
     * @param usdn The USDN token
     */
    struct WithdrawalData {
        uint128 pendingActionPrice;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        IUsdn usdn;
    }

    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        price_ = _calcUsdnPrice(
            vaultAssetAvailableWithFunding(currentPrice, timestamp).toUint256(),
            currentPrice,
            s._usdn.totalSupply(),
            s._assetDecimals
        );
    }

    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(currentPrice, uint128(block.timestamp));
    }

    /**
     * @notice Calculate an estimation of assets received when withdrawing
     * @param usdnShares The amount of USDN shares
     * @param price The price of the asset
     * @param timestamp The timestamp of the operation
     * @return assetExpected_ The expected amount of asset to be received
     */
    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        public
        view
        returns (uint256 assetExpected_)
    {
        // Apply fees on price
        uint128 withdrawalPriceWithFees = (price + price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();
        int256 available = vaultAssetAvailableWithFunding(withdrawalPriceWithFees, timestamp);
        if (available < 0) {
            return 0;
        }
        assetExpected_ = _calcBurnUsdn(usdnShares, uint256(available), s._usdn.totalShares());
    }

    /**
     * @notice Calculate the amount of sdex to burn when minting USDN tokens
     * @param usdnAmount The amount of usdn to be minted
     * @param sdexBurnRatio The ratio of SDEX to burn for each minted USDN
     * @return sdexToBurn_ The amount of SDEX to burn for the given USDN amount
     */
    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) internal view returns (uint256 sdexToBurn_) {
        sdexToBurn_ = FixedPointMathLib.fullMulDiv(usdnAmount, sdexBurnRatio, s.SDEX_BURN_ON_DEPOSIT_DIVISOR);
    }

    /**
     * @notice Get the lower 24 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares
     * @return sharesLSB_ The 24 least significant bits of the USDN shares
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Get the higher 128 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares
     * @return sharesMSB_ The 128 most significant bits of the USDN shares
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }

    function vaultAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert UsdnProtocolTimestampTooOld();
        }

        int256 ema = calcEMA(s._lastFunding, timestamp - s._lastUpdateTimestamp, s._EMAPeriod, s._EMA);
        (int256 fundAsset,) = _fundingAsset(timestamp, ema);

        if (fundAsset < 0) {
            available_ = _vaultAssetAvailable(currentPrice).safeAdd(fundAsset);
        } else {
            int256 fee = fundAsset * _toInt256(s._protocolFeeBps) / int256(s.BPS_DIVISOR);
            available_ = _vaultAssetAvailable(currentPrice).safeAdd(fundAsset - fee);
        }
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param currentPrice Current price
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(uint128 currentPrice) internal view returns (int256 available_) {
        available_ = _vaultAssetAvailable(s._totalExpo, s._balanceVault, s._balanceLong, currentPrice, s._lastPrice);
    }

    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateDeposit(msg.sender, to, amount, currentPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _validateDeposit(msg.sender, depositPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable initializedAndNonReentrant {
        uint256 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateWithdrawal(msg.sender, to, usdnShares, currentPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param user The address of the user initiating the withdrawal.
     * @param to The address that will receive the assets
     * @param usdnShares The amount of USDN shares to burn.
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateWithdrawal(address user, address to, uint152 usdnShares, bytes calldata currentPriceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (usdnShares == 0) {
            revert UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data = _prepareWithdrawalData(usdnShares, currentPriceData);

        securityDepositValue_ = _createWithdrawalPendingAction(user, to, usdnShares, data);

        // retrieve the USDN tokens, checks that balance is sufficient
        data.usdn.transferSharesFrom(user, address(this), usdnShares);

        emit InitiatedWithdrawal(user, to, data.usdn.convertToTokens(usdnShares), block.timestamp);
    }

    /**
     * @notice Prepare the pending action struct for a withdrawal and add it to the queue
     * @param user The address of the user initiating the withdrawal
     * @param to The address that will receive the assets
     * @param usdnShares The amount of USDN shares to burn
     * @param data The withdrawal action data
     * @return securityDepositValue_ The security deposit value
     */
    function _createWithdrawalPendingAction(address user, address to, uint152 usdnShares, WithdrawalData memory data)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory action = _convertWithdrawalPendingAction(
            WithdrawalPendingAction({
                action: ProtocolAction.ValidateWithdrawal,
                timestamp: uint40(block.timestamp),
                user: user,
                to: to,
                securityDepositValue: s._securityDepositValue,
                sharesLSB: _calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: _calcWithdrawalAmountMSB(usdnShares),
                assetPrice: data.pendingActionPrice,
                totalExpo: data.totalExpo,
                balanceVault: data.balanceVault,
                balanceLong: data.balanceLong,
                usdnTotalShares: data.usdn.totalShares()
            })
        );
        securityDepositValue_ = _addPendingAction(user, action);
    }

    /**
     * @notice Convert a `WithdrawalPendingAction` to a `PendingAction`
     * @param action A withdrawal pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        internal
        pure
        returns (PendingAction memory pendingAction_)
    {
        assembly {
            pendingAction_ := action
        }
    }

    /**
     * @notice Update protocol balances, then prepare the data for the withdrawal action.
     * @dev Reverts if the imbalance limit is reached.
     * @param usdnShares The amount of USDN shares to burn.
     * @param currentPriceData The current price data
     * @return data_ The withdrawal data struct
     */
    function _prepareWithdrawalData(uint152 usdnShares, bytes calldata currentPriceData)
        internal
        returns (WithdrawalData memory data_)
    {
        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateWithdrawal, block.timestamp, currentPriceData);

        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, currentPriceData
        );

        // Apply fees on price
        data_.pendingActionPrice =
            (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.balanceVault = _vaultAssetAvailable(
            data_.totalExpo, s._balanceVault, data_.balanceLong, data_.pendingActionPrice, s._lastPrice
        ).toUint256();
        data_.usdn = s._usdn;

        _checkImbalanceLimitWithdrawal(
            FixedPointMathLib.fullMulDiv(usdnShares, data_.balanceVault, data_.usdn.totalShares()), data_.totalExpo
        );
    }

    /**
     * @notice The withdrawal imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the withdrawal limit on long side, otherwise revert
     * @param withdrawalValue The withdrawal value in asset
     * @param totalExpo The current total expo
     */
    function _checkImbalanceLimitWithdrawal(uint256 withdrawalValue, uint256 totalExpo) internal view {
        int256 withdrawalExpoImbalanceLimitBps = s._withdrawalExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (withdrawalExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newVaultExpo = s._balanceVault.toInt256().safeSub(withdrawalValue.toInt256());

        // cannot be calculated if equal zero
        if (newVaultExpo == 0) {
            revert UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = ((totalExpo.toInt256().safeSub(s._balanceLong.toInt256())).safeSub(newVaultExpo)).safeMul(
            int256(s.BPS_DIVISOR)
        ).safeDiv(newVaultExpo);

        if (imbalanceBps >= withdrawalExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable
        initializedAndNonReentrant
    {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _validateWithdrawal(msg.sender, withdrawalPriceData);
        unchecked {
            amountToRefund += _executePendingActionOrRevert(previousActionsData);
        }
        _refundExcessEther(0, amountToRefund, balanceBefore);
        _checkPendingFee();
    }

    function _validateWithdrawal(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateWithdrawal) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateWithdrawalWithAction(pending, priceData);
        return pending.securityDepositValue;
    }

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param user The address of the user initiating the deposit.
     * @param to The address to receive the USDN tokens.
     * @param amount The amount of wstETH to deposit.
     * @param currentPriceData The current price data
     * @return securityDepositValue_ The security deposit value
     */
    function _initiateDeposit(address user, address to, uint128 amount, bytes calldata currentPriceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        if (to == address(0)) {
            revert UsdnProtocolInvalidAddressTo();
        }
        if (amount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        PriceInfo memory currentPrice =
            _getOraclePrice(ProtocolAction.InitiateDeposit, block.timestamp, currentPriceData);

        _applyPnlAndFundingAndLiquidate(
            currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, currentPriceData
        );

        _checkImbalanceLimitDeposit(amount);

        // Apply fees on price
        uint128 pendingActionPrice =
            (currentPrice.price - currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        DepositPendingAction memory pendingAction = DepositPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: s._securityDepositValue,
            _unused: 0,
            amount: amount,
            assetPrice: pendingActionPrice,
            totalExpo: s._totalExpo,
            balanceVault: _vaultAssetAvailable(
                s._totalExpo, s._balanceVault, s._balanceLong, pendingActionPrice, s._lastPrice
                ).toUint256(),
            balanceLong: s._balanceLong,
            usdnTotalSupply: s._usdn.totalSupply()
        });

        securityDepositValue_ = _addPendingAction(user, _convertDepositPendingAction(pendingAction));

        // Calculate the amount of SDEX tokens to burn
        uint256 usdnToMintEstimated = _calcMintUsdn(
            pendingAction.amount, pendingAction.balanceVault, pendingAction.usdnTotalSupply, pendingAction.assetPrice
        );
        uint32 burnRatio = s._sdexBurnOnDepositRatio;
        uint256 sdexToBurn = _calcSdexToBurn(usdnToMintEstimated, burnRatio);
        // We want to at least mint 1 wei of USDN
        if (usdnToMintEstimated == 0) {
            revert UsdnProtocolDepositTooSmall();
        }
        // We want to at least burn 1 wei of SDEX if SDEX burning is enabled
        if (burnRatio != 0 && sdexToBurn == 0) {
            revert UsdnProtocolDepositTooSmall();
        }
        if (sdexToBurn > 0) {
            // Send SDEX to the dead address
            s._sdex.safeTransferFrom(user, s.DEAD_ADDRESS, sdexToBurn);
        }

        // Transfer assets
        s._asset.safeTransferFrom(user, address(this), amount);

        emit InitiatedDeposit(user, to, amount, block.timestamp);
    }

    /**
     * @notice The deposit vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the deposit limit on vault side, otherwise revert
     * @param depositValue the deposit value in asset
     */
    function _checkImbalanceLimitDeposit(uint256 depositValue) internal view {
        int256 depositExpoImbalanceLimitBps = s._depositExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (depositExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentLongExpo = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());

        // cannot be calculated
        if (currentLongExpo == 0) {
            revert UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps = ((s._balanceVault + depositValue).toInt256().safeSub(currentLongExpo)).safeMul(
            int256(s.BPS_DIVISOR)
        ).safeDiv(currentLongExpo);

        if (imbalanceBps >= depositExpoImbalanceLimitBps) {
            revert UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    function _validateDeposit(address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = _getAndClearPendingAction(user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateDeposit) {
            revert UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert UsdnProtocolInvalidPendingAction();
        }

        _validateDepositWithAction(pending, priceData);
        return pending.securityDepositValue;
    }
}
