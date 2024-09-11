// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { DoubleEndedQueue } from "../../libraries/DoubleEndedQueue.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { Permit2TokenBitfield } from "../../libraries/Permit2TokenBitfield.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

library UsdnProtocolActionsVaultLibrary {
    using SafeTransferLib for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using LibBitmap for LibBitmap.Bitmap;
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;
    using Permit2TokenBitfield for Permit2TokenBitfield.Bitfield;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    /**
     * @notice Parameters for the internal `_initiateDeposit` function
     * @param user The address of the user initiating the deposit
     * @param to The address to receive the USDN tokens
     * @param validator The address that will validate the deposit
     * @param amount The amount of assets to deposit
     * @param sharesOutMin The minimum amount of USDN shares to receive
     * @param securityDepositValue The value of the security deposit for the newly created deposit
     * @param permit2TokenBitfield The permit2 bitfield
     */
    struct InitiateDepositParams {
        address user;
        address to;
        address validator;
        uint128 amount;
        uint256 sharesOutMin;
        uint64 securityDepositValue;
        Permit2TokenBitfield.Bitfield permit2TokenBitfield;
    }

    /**
     * @dev Structure to hold the transient data during `_initiateDeposit`
     * @param lastPrice The last price of the asset
     * @param isLiquidationPending Whether some liquidations still need to be performed
     * @param feeBps The vault deposit fee in basis points
     * @param totalExpo The total expo of the long side
     * @param balanceLong The long side balance
     * @param balanceVault The vault side balance, calculated according to the pendingActionPrice
     * @param usdnTotalShares Total minted shares of USDN
     * @param sdexToBurn The amount of SDEX to burn for the deposit
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
     * @dev Structure to hold the transient data during `_initiateWithdrawal`
     * @param usdnTotalShares The total shares supply of USDN
     * @param totalExpo The current total expo
     * @param balanceLong The current long balance
     * @param balanceVault The vault balance, adjusted according to the pendingActionPrice
     * @param withdrawalAmountAfterFees The predicted amount of assets that will be withdrawn after fees
     * @param lastPrice The last price of the asset
     * @param feeBps The vault deposit fee in basis points
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
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
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolActions}
    function initiateDeposit(
        Types.Storage storage s,
        uint128 amount,
        uint256 sharesOutMin,
        address to,
        address payable validator,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }
        uint256 balanceBefore = address(this).balance;

        uint256 validatorAmount;
        (validatorAmount, success_) = _initiateDeposit(
            s,
            InitiateDepositParams({
                user: msg.sender,
                to: to,
                validator: validator,
                amount: amount,
                sharesOutMin: sharesOutMin,
                securityDepositValue: securityDepositValue,
                permit2TokenBitfield: permit2TokenBitfield
            }),
            currentPriceData
        );

        uint256 amountToRefund;
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
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
        Utils._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateDeposit(
        Types.Storage storage s,
        address payable validator,
        bytes calldata depositPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _validateDeposit(s, validator, depositPriceData);
        if (msg.sender != validator) {
            Utils._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function initiateWithdrawal(
        Types.Storage storage s,
        uint152 usdnShares,
        uint256 amountOutMin,
        address to,
        address payable validator,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint64 securityDepositValue = s._securityDepositValue;
        if (msg.value < securityDepositValue) {
            revert IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow();
        }

        uint256 balanceBefore = address(this).balance;

        uint256 validatorAmount;
        (validatorAmount, success_) = _initiateWithdrawal(
            s, msg.sender, to, validator, usdnShares, amountOutMin, securityDepositValue, currentPriceData
        );

        uint256 amountToRefund;
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
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
        Utils._checkPendingFee(s);
    }

    /// @notice See {IUsdnProtocolActions}
    function validateWithdrawal(
        Types.Storage storage s,
        address payable validator,
        bytes calldata withdrawalPriceData,
        Types.PreviousActionsData calldata previousActionsData
    ) public returns (bool success_) {
        uint256 balanceBefore = address(this).balance;

        uint256 amountToRefund;
        (amountToRefund, success_) = _validateWithdrawal(s, validator, withdrawalPriceData);
        if (msg.sender != validator) {
            Utils._refundEther(amountToRefund, validator);
            balanceBefore -= amountToRefund;
            amountToRefund = 0;
        }
        if (success_) {
            unchecked {
                amountToRefund += _executePendingActionOrRevert(s, previousActionsData);
            }
        }

        Utils._refundExcessEther(0, amountToRefund, balanceBefore);
        Utils._checkPendingFee(s);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The deposit vault imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the deposit limit on the vault side, otherwise revert
     * @param s The storage of the protocol
     * @param depositValue The deposit value in asset
     */
    function _checkImbalanceLimitDeposit(Types.Storage storage s, uint256 depositValue) public view {
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
     * @notice The withdrawal imbalance limit state verification
     * @dev To ensure that the protocol does not imbalance more than
     * the withdrawal limit on the long side, otherwise revert
     * @param s The storage of the protocol
     * @param withdrawalValue The withdrawal value in asset
     * @param totalExpo The current total expo
     */
    function _checkImbalanceLimitWithdrawal(Types.Storage storage s, uint256 withdrawalValue, uint256 totalExpo)
        public
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
     * @notice Prepare the data for the `initiateDeposit` function
     * @param s The storage of the protocol
     * @param validator The validator address
     * @param amount The amount of asset to deposit
     * @param sharesOutMin The minimum amount of USDN shares to receive
     * @param currentPriceData The price data for the initiate action
     * @return data_ The transient data for the `deposit` action
     */
    function _prepareInitiateDepositData(
        Types.Storage storage s,
        address validator,
        uint128 amount,
        uint256 sharesOutMin,
        bytes calldata currentPriceData
    ) public returns (InitiateDepositData memory data_) {
        PriceInfo memory currentPrice = Utils._getOraclePrice(
            s,
            Types.ProtocolAction.InitiateDeposit,
            block.timestamp,
            Utils._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
            Types.ProtocolAction.InitiateDeposit,
            currentPriceData
        );

        if (data_.isLiquidationPending) {
            return data_;
        }

        _checkImbalanceLimitDeposit(s, amount);

        // apply fees on amount
        data_.feeBps = s._vaultFeeBps;
        uint128 amountAfterFees = (amount - uint256(amount) * data_.feeBps / Constants.BPS_DIVISOR).toUint128();

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.lastPrice = s._lastPrice;
        int256 available = Vault.vaultAssetAvailableWithFunding(s, data_.lastPrice, uint128(block.timestamp));
        if (available <= 0) {
            // can't mint USDN if the vault is empty
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }
        data_.balanceVault = uint256(available); // cast is safe, amount is positive
        IUsdn usdn = s._usdn;
        data_.usdnTotalShares = usdn.totalShares();

        // calculate the amount of SDEX tokens to burn
        uint256 usdnSharesToMintEstimated =
            Utils._calcMintUsdnShares(amountAfterFees, data_.balanceVault, data_.usdnTotalShares);
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
     * @notice Prepare the pending action struct for a deposit and add it to the queue
     * @param s The storage of the protocol
     * @param to The address that will receive the minted USDN
     * @param validator The address that will validate the deposit
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param amount The amount of assets to deposit (before fees)
     * @param data The deposit action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createDepositPendingAction(
        Types.Storage storage s,
        address to,
        address validator,
        uint64 securityDepositValue,
        uint128 amount,
        InitiateDepositData memory data
    ) public returns (uint256 amountToRefund_) {
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

        amountToRefund_ = Core._addPendingAction(s, validator, Utils._convertDepositPendingAction(pendingAction));
    }

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `Types.ProtocolAction.InitiateDeposit` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * @param s The storage of the protocol
     * @param params The parameters for the deposit
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     */
    function _initiateDeposit(
        Types.Storage storage s,
        InitiateDepositParams memory params,
        bytes calldata currentPriceData
    ) public returns (uint256 amountToRefund_, bool isInitiated_) {
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
            _prepareInitiateDepositData(s, params.validator, params.amount, params.sharesOutMin, currentPriceData);

        // early return in case there are still pending liquidations
        if (data.isLiquidationPending) {
            return (params.securityDepositValue, false);
        }

        amountToRefund_ = _createDepositPendingAction(
            s, params.to, params.validator, params.securityDepositValue, params.amount, data
        );

        if (data.sdexToBurn > 0) {
            // send SDEX to the dead address
            if (params.permit2TokenBitfield.useForSdex()) {
                address(s._sdex).permit2TransferFrom(params.user, Constants.DEAD_ADDRESS, data.sdexToBurn);
            } else {
                // slither-disable-next-line arbitrary-send-erc20
                address(s._sdex).safeTransferFrom(params.user, Constants.DEAD_ADDRESS, data.sdexToBurn);
            }
        }

        // transfer assets
        if (params.permit2TokenBitfield.useForAsset()) {
            address(s._asset).permit2TransferFrom(params.user, address(this), params.amount);
        } else {
            // slither-disable-next-line arbitrary-send-erc20
            address(s._asset).safeTransferFrom(params.user, address(this), params.amount);
        }
        s._pendingBalanceVault += Utils.toInt256(params.amount);

        isInitiated_ = true;

        emit IUsdnProtocolEvents.InitiatedDeposit(
            params.to, params.validator, params.amount, data.feeBps, block.timestamp, data.sdexToBurn
        );
    }

    /**
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param s The storage of the protocol
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     */
    function _validateDeposit(Types.Storage storage s, address validator, bytes calldata priceData)
        public
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateDeposit) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        isValidated_ = _validateDepositWithAction(s, pending, priceData);

        if (isValidated_) {
            Utils._clearPendingAction(s, validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the `deposit` action
     * @param s The storage of the protocol
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     */
    function _validateDepositWithAction(
        Types.Storage storage s,
        Types.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (bool isValidated_) {
        Types.DepositPendingAction memory deposit = Utils._toDepositPendingAction(pending);

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            s,
            Types.ProtocolAction.ValidateDeposit,
            deposit.timestamp,
            Utils._calcActionId(deposit.validator, deposit.timestamp),
            priceData
        );

        {
            // adjust balances
            (, bool isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
                s,
                currentPrice.neutralPrice,
                currentPrice.timestamp,
                s._liquidationIteration,
                false,
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
        // the initiate and validate actions is ignored
        uint128 amountAfterFees =
            (deposit.amount - uint256(deposit.amount) * deposit.feeBps / Constants.BPS_DIVISOR).toUint128();

        uint256 balanceVault = deposit.balanceVault;
        if (currentPrice.price < deposit.assetPrice) {
            // price decreased: balance of the vault increased
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
        s._pendingBalanceVault -= Utils.toInt256(deposit.amount);

        uint256 mintedTokens = s._usdn.mintShares(
            deposit.to, Utils._calcMintUsdnShares(amountAfterFees, balanceVault, deposit.usdnTotalShares)
        );
        isValidated_ = true;
        emit IUsdnProtocolEvents.ValidatedDeposit(
            deposit.to, deposit.validator, amountAfterFees, mintedTokens, deposit.timestamp
        );
    }

    /**
     * @notice Update protocol balances, then prepare the data for the withdrawal action
     * @dev Reverts if the imbalance limit is reached
     * @param s The storage of the protocol
     * @param validator The validator address
     * @param usdnShares The amount of USDN shares to burn
     * @param amountOutMin The estimated minimum amount of assets to receive
     * @param currentPriceData The current price data
     * @return data_ The withdrawal data struct
     */
    function _prepareWithdrawalData(
        Types.Storage storage s,
        address validator,
        uint152 usdnShares,
        uint256 amountOutMin,
        bytes calldata currentPriceData
    ) public returns (WithdrawalData memory data_) {
        PriceInfo memory currentPrice = Utils._getOraclePrice(
            s,
            Types.ProtocolAction.InitiateWithdrawal,
            block.timestamp,
            Utils._calcActionId(validator, uint128(block.timestamp)),
            currentPriceData
        );

        (, data_.isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
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
        int256 available = Vault.vaultAssetAvailableWithFunding(s, data_.lastPrice, uint128(block.timestamp));
        if (available < 0) {
            available = 0;
        }
        data_.balanceVault = uint256(available); // cast is safe, amount is positive
        data_.usdnTotalShares = s._usdn.totalShares();
        data_.feeBps = s._vaultFeeBps;
        data_.withdrawalAmountAfterFees =
            Utils._calcBurnUsdn(usdnShares, data_.balanceVault, data_.usdnTotalShares, data_.feeBps);
        if (data_.withdrawalAmountAfterFees < amountOutMin) {
            revert IUsdnProtocolErrors.UsdnProtocolAmountReceivedTooSmall();
        }
        _checkImbalanceLimitWithdrawal(s, data_.withdrawalAmountAfterFees, data_.totalExpo);
    }

    /**
     * @notice Prepare the pending action struct for a withdrawal and add it to the queue
     * @param s The storage of the protocol
     * @param to The address that will receive the assets
     * @param validator The address that will validate the withdrawal
     * @param usdnShares The amount of USDN shares to burn
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param data The withdrawal action data
     * @return amountToRefund_ Refund The security deposit value of a stale pending action
     */
    function _createWithdrawalPendingAction(
        Types.Storage storage s,
        address to,
        address validator,
        uint152 usdnShares,
        uint64 securityDepositValue,
        WithdrawalData memory data
    ) public returns (uint256 amountToRefund_) {
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
        amountToRefund_ = Core._addPendingAction(s, validator, action);
    }

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `Types.ProtocolAction.InitiateWithdrawal` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * @param s The storage of the protocol
     * @param user The address of the user initiating the withdrawal
     * @param to The address that will receive the assets
     * @param validator The address that will validate the withdrawal
     * @param usdnShares The amount of USDN shares to burn
     * @param amountOutMin The estimated minimum amount of assets to receive
     * @param securityDepositValue The value of the security deposit for the newly created pending action
     * @param currentPriceData The current price data
     * @return amountToRefund_ If there are pending liquidations we'll refund the `securityDepositValue`,
     * else we'll only refund the security deposit value of the stale pending action
     * @return isInitiated_ Whether the action is initiated
     */
    function _initiateWithdrawal(
        Types.Storage storage s,
        address user,
        address to,
        address validator,
        uint152 usdnShares,
        uint256 amountOutMin,
        uint64 securityDepositValue,
        bytes calldata currentPriceData
    ) public returns (uint256 amountToRefund_, bool isInitiated_) {
        if (to == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo();
        }
        if (validator == address(0)) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator();
        }
        if (usdnShares == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolZeroAmount();
        }

        WithdrawalData memory data = _prepareWithdrawalData(s, validator, usdnShares, amountOutMin, currentPriceData);

        if (data.isLiquidationPending) {
            return (securityDepositValue, false);
        }

        amountToRefund_ = _createWithdrawalPendingAction(s, to, validator, usdnShares, securityDepositValue, data);

        // retrieve the USDN tokens, check that the balance is sufficient
        IUsdn usdn = s._usdn;
        usdn.transferSharesFrom(user, address(this), usdnShares);
        // register the pending withdrawal for imbalance checks of future actions
        s._pendingBalanceVault -= data.withdrawalAmountAfterFees.toInt256();

        isInitiated_ = true;
        emit IUsdnProtocolEvents.InitiatedWithdrawal(
            to, validator, usdn.convertToTokens(usdnShares), data.feeBps, block.timestamp
        );
    }

    /**
     * @notice Get the pending action data of the owner, try to validate it and clear it if successful
     * @param s The storage of the protocol
     * @param validator The address of the validator
     * @param priceData The current price data
     * @return securityDepositValue_ The value of the security deposit
     * @return isValidated_ Whether the action is validated
     */
    function _validateWithdrawal(Types.Storage storage s, address validator, bytes calldata priceData)
        public
        returns (uint256 securityDepositValue_, bool isValidated_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getPendingActionOrRevert(s, validator);

        // check type of action
        if (pending.action != Types.ProtocolAction.ValidateWithdrawal) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }
        // sanity check
        if (pending.validator != validator) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction();
        }

        isValidated_ = _validateWithdrawalWithAction(s, pending, priceData);

        if (isValidated_) {
            Utils._clearPendingAction(s, validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
        }
    }

    /**
     * @notice Update protocol balances, liquidate positions if necessary, then validate the `withdrawal` action
     * @param s The storage of the protocol
     * @param pending The pending action data
     * @param priceData The current price data
     * @return isValidated_ Whether the action is validated
     */
    function _validateWithdrawalWithAction(
        Types.Storage storage s,
        Types.PendingAction memory pending,
        bytes calldata priceData
    ) public returns (bool isValidated_) {
        Types.WithdrawalPendingAction memory withdrawal = Utils._toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice = Utils._getOraclePrice(
            s,
            Types.ProtocolAction.ValidateWithdrawal,
            withdrawal.timestamp,
            Utils._calcActionId(withdrawal.validator, withdrawal.timestamp),
            priceData
        );

        (, bool isLiquidationPending) = Long._applyPnlAndFundingAndLiquidate(
            s,
            currentPrice.neutralPrice,
            currentPrice.timestamp,
            s._liquidationIteration,
            false,
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
            Utils._calcBurnUsdn(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares, withdrawal.feeBps);
        s._pendingBalanceVault += tempWithdrawalAfterFees.toInt256();

        IUsdn usdn = s._usdn;
        // calculate the amount of asset to transfer with the same fees as recorded during the initiate action
        uint256 assetToTransferAfterFees = Utils._calcBurnUsdn(shares, available, usdn.totalShares(), withdrawal.feeBps);

        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransferAfterFees > 0) {
            s._balanceVault -= assetToTransferAfterFees;
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
     * @notice Execute the first actionable pending action or revert if the price data was not provided
     * @param s The storage of the protocol
     * @param data The price data and raw indices
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingActionOrRevert(Types.Storage storage s, Types.PreviousActionsData calldata data)
        public
        returns (uint256 securityDepositValue_)
    {
        bool success;
        (success,,, securityDepositValue_) = _executePendingAction(s, data);
        if (!success) {
            revert IUsdnProtocolErrors.UsdnProtocolInvalidPendingActionData();
        }
    }

    /**
     * @notice Execute the first actionable pending action and report the success
     * @param s The storage of the protocol
     * @param data The price data and raw indices
     * @return success_ Whether the price data is valid
     * @return executed_ Whether the pending action was executed (false if the queue has no actionable item)
     * @return liquidated_ Whether the position corresponding to the pending action was liquidated
     * @return securityDepositValue_ The security deposit value of the executed action
     */
    function _executePendingAction(Types.Storage storage s, Types.PreviousActionsData calldata data)
        public
        returns (bool success_, bool executed_, bool liquidated_, uint256 securityDepositValue_)
    {
        (Types.PendingAction memory pending, uint128 rawIndex) = Core._getActionablePendingAction(s);
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
            executed_ = _validateDepositWithAction(s, pending, priceData);
        } else if (pending.action == Types.ProtocolAction.ValidateWithdrawal) {
            executed_ = _validateWithdrawalWithAction(s, pending, priceData);
        } else if (pending.action == Types.ProtocolAction.ValidateOpenPosition) {
            (executed_, liquidated_) = ActionsLong._validateOpenPositionWithAction(s, pending, priceData);
        } else if (pending.action == Types.ProtocolAction.ValidateClosePosition) {
            (executed_, liquidated_) = ActionsLong._validateClosePositionWithAction(s, pending, priceData);
        }

        success_ = true;

        if (executed_ || liquidated_) {
            Utils._clearPendingAction(s, pending.validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
            emit IUsdnProtocolEvents.SecurityDepositRefunded(pending.validator, msg.sender, securityDepositValue_);
        }
    }

    /**
     * @notice Get the lower 24 bits of the withdrawal amount (USDN shares)
     * @param usdnShares The amount of USDN shares
     * @return sharesLSB_ The 24 least significant bits of the USDN shares
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Get the higher 128 bits of the withdrawal amount (USDN shares)
     * @param usdnShares The amount of USDN shares
     * @return sharesMSB_ The 128 most significant bits of the USDN shares
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }
}
