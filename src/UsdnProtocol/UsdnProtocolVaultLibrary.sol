// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

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
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { HugeUint } from "src/libraries/HugeUint.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { UsdnProtocolCommonLibrary as lib } from "src/UsdnProtocol/UsdnProtocolCommonLibrary.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Storage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";

library UsdnProtocolVaultLibrary {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IUsdn;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /**
     * @notice Emitted when a user initiates a withdrawal
     * @param user The user address
     * @param to The address that will receive the assets
     * @param usdnAmount The amount of USDN that will be burned
     * @param timestamp The timestamp of the action
     */
    event InitiatedWithdrawal(address indexed user, address indexed to, uint256 usdnAmount, uint256 timestamp);

    /**
     * @notice Emitted when a user initiates a deposit
     * @param user The user address
     * @param to The address that will receive the USDN tokens
     * @param amount The amount of asset that were deposited
     * @param timestamp The timestamp of the action
     */
    event InitiatedDeposit(address indexed user, address indexed to, uint256 amount, uint256 timestamp);

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

    function usdnPrice(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (uint256 price_)
    {
        price_ = lib._calcUsdnPrice(
            s,
            vaultAssetAvailableWithFunding(s, currentPrice, timestamp).toUint256(),
            currentPrice,
            s._usdn.totalSupply(),
            s._assetDecimals
        );
    }

    function usdnPrice(Storage storage s, uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(s, currentPrice, uint128(block.timestamp));
    }

    function getUserPendingAction(Storage storage s, address user)
        external
        view
        returns (PendingAction memory action_)
    {
        (action_,) = lib._getPendingAction(s, user);
    }

    function getActionablePendingActions(Storage storage s, address currentUser)
        external
        view
        returns (PendingAction[] memory actions_, uint128[] memory rawIndices_)
    {
        uint256 queueLength = s._pendingActionsQueue.length();
        if (queueLength == 0) {
            // empty queue, early return
            return (actions_, rawIndices_);
        }
        actions_ = new PendingAction[](s.MAX_ACTIONABLE_PENDING_ACTIONS);
        rawIndices_ = new uint128[](s.MAX_ACTIONABLE_PENDING_ACTIONS);
        uint256 maxIter = s.MAX_ACTIONABLE_PENDING_ACTIONS;
        if (queueLength < maxIter) {
            maxIter = queueLength;
        }

        uint256 i = 0;
        uint256 arrayLen = 0;
        do {
            // since `i` cannot be greater or equal to `queueLength`, there is no risk of reverting
            (PendingAction memory candidate, uint128 rawIndex) = s._pendingActionsQueue.at(i);

            // if the msg.sender is equal to the user of the pending action, then the pending action is not actionable
            // by this user (it will get validated automatically by their action)
            // and so we need to return the next item in the queue so that they can validate a third-party pending
            // action (if any)
            if (candidate.timestamp == 0 || candidate.user == currentUser) {
                rawIndices_[i] = rawIndex;
                // try the next one
                unchecked {
                    i++;
                }
            } else if (candidate.timestamp + s._validationDeadline < block.timestamp) {
                // we found an actionable pending action
                actions_[i] = candidate;
                rawIndices_[i] = rawIndex;

                // continue looking
                unchecked {
                    i++;
                    arrayLen = i;
                }
            } else {
                // the pending action is not actionable (it is too recent),
                // following actions can't be actionable either so we return
                break;
            }
        } while (i < maxIter);
        assembly {
            // shrink the size of the arrays
            mstore(actions_, arrayLen)
            mstore(rawIndices_, arrayLen)
        }
    }

    function vaultTradingExpoWithFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        external
        view
        returns (int256 expo_)
    {
        expo_ = vaultAssetAvailableWithFunding(s, currentPrice, timestamp);
    }

    /**
     * @notice Calculate an estimation of assets received when withdrawing
     * @param usdnShares The amount of USDN shares
     * @param price The price of the asset
     * @param timestamp The timestamp of the operation
     * @return assetExpected_ The expected amount of asset to be received
     */
    function previewWithdraw(Storage storage s, uint256 usdnShares, uint256 price, uint128 timestamp)
        public
        view
        returns (uint256 assetExpected_)
    {
        // Apply fees on price
        uint128 withdrawalPriceWithFees = (price + price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();
        int256 available = vaultAssetAvailableWithFunding(s, withdrawalPriceWithFees, timestamp);
        if (available < 0) {
            return 0;
        }
        assetExpected_ = lib._calcBurnUsdn(usdnShares, uint256(available), s._usdn.totalShares());
    }

    /**
     * @notice Calculate the amount of sdex to burn when minting USDN tokens
     * @param usdnAmount The amount of usdn to be minted
     * @param sdexBurnRatio The ratio of SDEX to burn for each minted USDN
     * @return sdexToBurn_ The amount of SDEX to burn for the given USDN amount
     */
    function _calcSdexToBurn(Storage storage s, uint256 usdnAmount, uint32 sdexBurnRatio)
        public
        view
        returns (uint256 sdexToBurn_)
    {
        sdexToBurn_ = FixedPointMathLib.fullMulDiv(usdnAmount, sdexBurnRatio, s.SDEX_BURN_ON_DEPOSIT_DIVISOR);
    }

    /**
     * @notice Get the lower 24 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares
     * @return sharesLSB_ The 24 least significant bits of the USDN shares
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) public pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Get the higher 128 bits of the withdrawal amount (USDN shares).
     * @param usdnShares The amount of USDN shares
     * @return sharesMSB_ The 128 most significant bits of the USDN shares
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) public pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }

    function vaultAssetAvailableWithFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        int256 ema = lib.calcEMA(s._lastFunding, timestamp - s._lastUpdateTimestamp, s._EMAPeriod, s._EMA);
        (int256 fundAsset,) = lib._fundingAsset(s, timestamp, ema);

        if (fundAsset < 0) {
            available_ = _vaultAssetAvailable(s, currentPrice).safeAdd(fundAsset);
        } else {
            int256 fee = fundAsset * lib._toInt256(s._protocolFeeBps) / int256(s.BPS_DIVISOR);
            available_ = _vaultAssetAvailable(s, currentPrice).safeAdd(fundAsset - fee);
        }
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param currentPrice Current price
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(Storage storage s, uint128 currentPrice) public view returns (int256 available_) {
        available_ = lib._vaultAssetAvailable(s._totalExpo, s._balanceVault, s._balanceLong, currentPrice, s._lastPrice);
    }

    function initiateDeposit(
        Storage storage s,
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external {
        uint256 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateDeposit(s, msg.sender, to, amount, currentPriceData);
        unchecked {
            amountToRefund += lib._executePendingActionOrRevert(s, previousActionsData);
        }
        lib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        lib._checkPendingFee(s);
    }

    function validateDeposit(
        Storage storage s,
        bytes calldata depositPriceData,
        PreviousActionsData calldata previousActionsData
    ) external {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _validateDeposit(s, msg.sender, depositPriceData);
        unchecked {
            amountToRefund += lib._executePendingActionOrRevert(s, previousActionsData);
        }
        lib._refundExcessEther(0, amountToRefund, balanceBefore);
        lib._checkPendingFee(s);
    }

    function initiateWithdrawal(
        Storage storage s,
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external {
        uint256 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _initiateWithdrawal(s, msg.sender, to, usdnShares, currentPriceData);
        unchecked {
            amountToRefund += lib._executePendingActionOrRevert(s, previousActionsData);
        }
        lib._refundExcessEther(securityDepositValue, amountToRefund, balanceBefore);
        lib._checkPendingFee(s);
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
    function _initiateWithdrawal(
        Storage storage s,
        address user,
        address to,
        uint152 usdnShares,
        bytes calldata currentPriceData
    ) internal returns (uint256 securityDepositValue_) {
        if (to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (usdnShares == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data = _prepareWithdrawalData(s, usdnShares, currentPriceData);

        securityDepositValue_ = _createWithdrawalPendingAction(s, user, to, usdnShares, data);

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
    function _createWithdrawalPendingAction(
        Storage storage s,
        address user,
        address to,
        uint152 usdnShares,
        WithdrawalData memory data
    ) internal returns (uint256 securityDepositValue_) {
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
        securityDepositValue_ = lib._addPendingAction(s, user, action);
    }

    /**
     * @notice Convert a `WithdrawalPendingAction` to a `PendingAction`
     * @param action A withdrawal pending action
     * @return pendingAction_ The converted untyped pending action
     */
    function _convertWithdrawalPendingAction(WithdrawalPendingAction memory action)
        public
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
    function _prepareWithdrawalData(Storage storage s, uint152 usdnShares, bytes calldata currentPriceData)
        internal
        returns (WithdrawalData memory data_)
    {
        PriceInfo memory currentPrice =
            lib._getOraclePrice(s, ProtocolAction.InitiateWithdrawal, block.timestamp, currentPriceData);

        lib._applyPnlAndFundingAndLiquidate(
            s, currentPrice.neutralPrice, currentPrice.timestamp, s._liquidationIteration, false, currentPriceData
        );

        // Apply fees on price
        data_.pendingActionPrice =
            (currentPrice.price + currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.balanceVault = lib._vaultAssetAvailable(
            data_.totalExpo, s._balanceVault, data_.balanceLong, data_.pendingActionPrice, s._lastPrice
        ).toUint256();
        data_.usdn = s._usdn;

        _checkImbalanceLimitWithdrawal(
            s, FixedPointMathLib.fullMulDiv(usdnShares, data_.balanceVault, data_.usdn.totalShares()), data_.totalExpo
        );
    }

    /**
     * @notice The withdrawal imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the withdrawal limit on long side, otherwise revert
     * @param withdrawalValue The withdrawal value in asset
     * @param totalExpo The current total expo
     */
    function _checkImbalanceLimitWithdrawal(Storage storage s, uint256 withdrawalValue, uint256 totalExpo)
        public
        view
    {
        int256 withdrawalExpoImbalanceLimitBps = s._withdrawalExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (withdrawalExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 newVaultExpo = s._balanceVault.toInt256().safeSub(withdrawalValue.toInt256());

        // cannot be calculated if equal zero
        if (newVaultExpo == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo();
        }

        int256 imbalanceBps = ((totalExpo.toInt256().safeSub(s._balanceLong.toInt256())).safeSub(newVaultExpo)).safeMul(
            int256(s.BPS_DIVISOR)
        ).safeDiv(newVaultExpo);

        if (imbalanceBps >= withdrawalExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    function validateWithdrawal(
        Storage storage s,
        bytes calldata withdrawalPriceData,
        PreviousActionsData calldata previousActionsData
    ) external {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund = _validateWithdrawal(s, msg.sender, withdrawalPriceData);
        unchecked {
            amountToRefund += lib._executePendingActionOrRevert(s, previousActionsData);
        }
        lib._refundExcessEther(0, amountToRefund, balanceBefore);
        lib._checkPendingFee(s);
    }

    function _validateWithdrawal(Storage storage s, address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = lib._getAndClearPendingAction(s, user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateWithdrawal) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        lib._validateWithdrawalWithAction(s, pending, priceData);
        return pending.securityDepositValue;
    }

    struct InitiateDepositData {
        PriceInfo currentPrice;
        uint128 pendingActionPrice;
        DepositPendingAction pendingAction;
        uint256 balanceVault;
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
    function _initiateDeposit(
        Storage storage s,
        address user,
        address to,
        uint128 amount,
        bytes calldata currentPriceData
    ) internal returns (uint256 securityDepositValue_) {
        if (to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (amount == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }
        InitiateDepositData memory data;

        data.currentPrice = lib._getOraclePrice(s, ProtocolAction.InitiateDeposit, block.timestamp, currentPriceData);

        lib._applyPnlAndFundingAndLiquidate(
            s,
            data.currentPrice.neutralPrice,
            data.currentPrice.timestamp,
            s._liquidationIteration,
            false,
            currentPriceData
        );

        _checkImbalanceLimitDeposit(s, amount);

        // Apply fees on price
        data.pendingActionPrice =
            (data.currentPrice.price - data.currentPrice.price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();

        data.balanceVault = lib._vaultAssetAvailable(
            s._totalExpo, s._balanceVault, s._balanceLong, data.pendingActionPrice, s._lastPrice
        ).toUint256();

        data.pendingAction = DepositPendingAction({
            action: ProtocolAction.ValidateDeposit,
            timestamp: uint40(block.timestamp),
            user: user,
            to: to,
            securityDepositValue: s._securityDepositValue,
            _unused: 0,
            amount: amount,
            assetPrice: data.pendingActionPrice,
            totalExpo: s._totalExpo,
            balanceVault: data.balanceVault,
            balanceLong: s._balanceLong,
            usdnTotalSupply: s._usdn.totalSupply()
        });

        securityDepositValue_ = lib._addPendingAction(s, user, lib._convertDepositPendingAction(data.pendingAction));

        // Calculate the amount of SDEX tokens to burn
        uint256 usdnToMintEstimated = lib._calcMintUsdn(
            s,
            data.pendingAction.amount,
            data.pendingAction.balanceVault,
            data.pendingAction.usdnTotalSupply,
            data.pendingAction.assetPrice
        );
        uint32 burnRatio = s._sdexBurnOnDepositRatio;
        uint256 sdexToBurn = _calcSdexToBurn(s, usdnToMintEstimated, burnRatio);
        // We want to at least mint 1 wei of USDN
        if (usdnToMintEstimated == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
        }
        // We want to at least burn 1 wei of SDEX if SDEX burning is enabled
        if (burnRatio != 0 && sdexToBurn == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
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
    function _checkImbalanceLimitDeposit(Storage storage s, uint256 depositValue) public view {
        int256 depositExpoImbalanceLimitBps = s._depositExpoImbalanceLimitBps;

        // early return in case limit is disabled
        if (depositExpoImbalanceLimitBps == 0) {
            return;
        }

        int256 currentLongExpo = s._totalExpo.toInt256().safeSub(s._balanceLong.toInt256());

        // cannot be calculated
        if (currentLongExpo == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo();
        }

        int256 imbalanceBps = ((s._balanceVault + depositValue).toInt256().safeSub(currentLongExpo)).safeMul(
            int256(s.BPS_DIVISOR)
        ).safeDiv(currentLongExpo);

        if (imbalanceBps >= depositExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    function _validateDeposit(Storage storage s, address user, bytes calldata priceData)
        internal
        returns (uint256 securityDepositValue_)
    {
        PendingAction memory pending = lib._getAndClearPendingAction(s, user);

        // check type of action
        if (pending.action != ProtocolAction.ValidateDeposit) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.user != user) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        lib._validateDepositWithAction(s, pending, priceData);
        return pending.securityDepositValue;
    }
}
