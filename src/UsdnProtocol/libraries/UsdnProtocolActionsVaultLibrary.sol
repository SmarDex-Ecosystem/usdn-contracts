// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { LibBitmap } from "solady/src/utils/LibBitmap.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IFeeCollectorCallback } from "../../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IUsdnProtocolActions } from "../../interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../libraries/HugeUint.sol";
import { Permit2TokenBitfield } from "../../libraries/Permit2TokenBitfield.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { UsdnProtocolActionsLongLibrary as ActionsLong } from "./UsdnProtocolActionsLongLibrary.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "./UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtils as Utils } from "./UsdnProtocolUtils.sol";
import { UsdnProtocolVaultLibrary as Vault } from "./UsdnProtocolVaultLibrary.sol";

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
     * @param withdrawalAmountWithFees The predicted amount of assets that will be withdrawn after fees
     * @param lastPrice The last price of the asset
     * @param feeBps The vault deposit fee in basis points
     * @param isLiquidationPending Whether some ticks are still populated above the current price (left to liquidate)
     */
    struct WithdrawalData {
        uint256 usdnTotalShares;
        uint256 totalExpo;
        uint256 balanceLong;
        uint256 balanceVault;
        uint256 withdrawalAmountWithFees;
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

    /// @notice See {IUsdnProtocolActions}
    function initiateWithdrawal(
        Types.Storage storage s,
        uint152 usdnShares,
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

        if (imbalanceBps >= depositExpoImbalanceLimitBps) {
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

        if (imbalanceBps >= withdrawalExpoImbalanceLimitBps) {
            revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
        }
    }

    /**
     * @notice Prepare the data for the `initiateDeposit` function
     * @param s The storage of the protocol
     * @param validator The validator address
     * @param amount The amount of asset to deposit
     * @param currentPriceData The price data for the initiate action
     * @return data_ The transient data for the `deposit` action
     */
    function _prepareInitiateDepositData(
        Types.Storage storage s,
        address validator,
        uint128 amount,
        bytes calldata currentPriceData
    ) public returns (InitiateDepositData memory data_) {
        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            Types.ProtocolAction.InitiateDeposit,
            block.timestamp,
            ActionsUtils._calcActionId(validator, uint128(block.timestamp)),
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
        uint128 amountWithFees = (amount - uint256(amount) * data_.feeBps / Constants.BPS_DIVISOR).toUint128();

        data_.totalExpo = s._totalExpo;
        data_.balanceLong = s._balanceLong;
        data_.lastPrice = s._lastPrice;
        data_.balanceVault =
            Vault.vaultAssetAvailableWithFunding(s, data_.lastPrice, uint128(block.timestamp)).toUint256();
        IUsdn usdn = s._usdn;
        data_.usdnTotalShares = usdn.totalShares();

        // calculate the amount of SDEX tokens to burn
        uint256 usdnSharesToMintEstimated =
            Vault._calcMintUsdnShares(amountWithFees, data_.balanceVault, data_.usdnTotalShares);
        uint256 usdnToMintEstimated = usdn.convertToTokens(usdnSharesToMintEstimated);
        // we want to at least mint 1 wei of USDN
        if (usdnToMintEstimated == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
        }
        uint32 burnRatio = s._sdexBurnOnDepositRatio;
        data_.sdexToBurn = Vault._calcSdexToBurn(usdnToMintEstimated, burnRatio);
        // we want to at least burn 1 wei of SDEX if SDEX burning is enabled
        if (burnRatio != 0 && data_.sdexToBurn == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolDepositTooSmall();
        }
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

        amountToRefund_ = Core._addPendingAction(s, validator, Core._convertDepositPendingAction(pendingAction));
    }

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `Types.ProtocolAction.InitiateDeposit` action
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware
     * @param s The storage of the protocol
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
        Types.Storage storage s,
        address user,
        address to,
        address validator,
        uint128 amount,
        uint64 securityDepositValue,
        Permit2TokenBitfield.Bitfield permit2TokenBitfield,
        bytes calldata currentPriceData
    ) public returns (uint256 amountToRefund_, bool isInitiated_) {
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
                address(s._sdex).permit2TransferFrom(user, Constants.DEAD_ADDRESS, data.sdexToBurn);
            } else {
                // slither-disable-next-line arbitrary-send-erc20
                address(s._sdex).safeTransferFrom(user, Constants.DEAD_ADDRESS, data.sdexToBurn);
            }
        }

        // transfer assets
        if (permit2TokenBitfield.useForAsset()) {
            address(s._asset).permit2TransferFrom(user, address(this), amount);
        } else {
            // slither-disable-next-line arbitrary-send-erc20
            address(s._asset).safeTransferFrom(user, address(this), amount);
        }
        s._pendingBalanceVault += Utils.toInt256(amount);

        isInitiated_ = true;

        emit IUsdnProtocolEvents.InitiatedDeposit(to, validator, amount, data.feeBps, block.timestamp, data.sdexToBurn);
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
            Core._clearPendingAction(s, validator, rawIndex);
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
        Types.DepositPendingAction memory deposit = Core._toDepositPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            Types.ProtocolAction.ValidateDeposit,
            deposit.timestamp,
            ActionsUtils._calcActionId(deposit.validator, deposit.timestamp),
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
        uint128 amountWithFees =
            (deposit.amount - uint256(deposit.amount) * deposit.feeBps / Constants.BPS_DIVISOR).toUint128();
        int256 available = Vault._vaultAssetAvailable(
            deposit.totalExpo,
            deposit.balanceVault,
            deposit.balanceLong,
            currentPrice.price.toUint128(),
            deposit.assetPrice
        );
        if (available < 0) {
            available = 0;
        }
        uint256 balanceVault = uint256(available);
        if (deposit.balanceVault > balanceVault) {
            balanceVault = deposit.balanceVault;
        }
        uint256 usdnSharesToMint = Vault._calcMintUsdnShares(amountWithFees, balanceVault, deposit.usdnTotalShares);

        s._balanceVault += deposit.amount; // we credit the full deposit amount
        s._pendingBalanceVault -= Utils.toInt256(deposit.amount);

        uint256 mintedTokens = s._usdn.mintShares(deposit.to, usdnSharesToMint);
        isValidated_ = true;
        emit IUsdnProtocolEvents.ValidatedDeposit(
            deposit.to, deposit.validator, amountWithFees, mintedTokens, deposit.timestamp
        );
    }

    /**
     * @notice Update protocol balances, then prepare the data for the withdrawal action
     * @dev Reverts if the imbalance limit is reached
     * @param s The storage of the protocol
     * @param validator The validator address
     * @param usdnShares The amount of USDN shares to burn
     * @param currentPriceData The current price data
     * @return data_ The withdrawal data struct
     */
    function _prepareWithdrawalData(
        Types.Storage storage s,
        address validator,
        uint152 usdnShares,
        bytes calldata currentPriceData
    ) public returns (WithdrawalData memory data_) {
        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            Types.ProtocolAction.InitiateWithdrawal,
            block.timestamp,
            ActionsUtils._calcActionId(validator, uint128(block.timestamp)),
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
        data_.withdrawalAmountWithFees =
            Vault._calcBurnUsdn(usdnShares, data_.balanceVault, data_.usdnTotalShares, data_.feeBps);

        _checkImbalanceLimitWithdrawal(s, data_.withdrawalAmountWithFees, data_.totalExpo);
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
        Types.PendingAction memory action = Core._convertWithdrawalPendingAction(
            Types.WithdrawalPendingAction({
                action: Types.ProtocolAction.ValidateWithdrawal,
                timestamp: uint40(block.timestamp),
                feeBps: data.feeBps,
                to: to,
                validator: validator,
                securityDepositValue: securityDepositValue,
                sharesLSB: Vault._calcWithdrawalAmountLSB(usdnShares),
                sharesMSB: Vault._calcWithdrawalAmountMSB(usdnShares),
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
     * @notice Get the oracle price for the given action and timestamp then validate it
     * @param s The storage of the protocol
     * @param action The type of action that is being performed by the user
     * @param timestamp The timestamp at which the wanted price was recorded
     * @param actionId The unique identifier of the action
     * @param priceData The price oracle data
     * @return price_ The validated price
     */
    function _getOraclePrice(
        Types.Storage storage s,
        Types.ProtocolAction action,
        uint256 timestamp,
        bytes32 actionId,
        bytes calldata priceData
    ) public returns (PriceInfo memory price_) {
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

        WithdrawalData memory data = _prepareWithdrawalData(s, validator, usdnShares, currentPriceData);

        if (data.isLiquidationPending) {
            return (securityDepositValue, false);
        }

        amountToRefund_ = _createWithdrawalPendingAction(s, to, validator, usdnShares, securityDepositValue, data);

        // retrieve the USDN tokens, check that the balance is sufficient
        IUsdn usdn = s._usdn;
        usdn.transferSharesFrom(user, address(this), usdnShares);
        // register the pending withdrawal for imbalance checks of future actions
        s._pendingBalanceVault -= data.withdrawalAmountWithFees.toInt256();

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
            Core._clearPendingAction(s, validator, rawIndex);
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
        Types.WithdrawalPendingAction memory withdrawal = Core._toWithdrawalPendingAction(pending);

        PriceInfo memory currentPrice = _getOraclePrice(
            s,
            Types.ProtocolAction.ValidateWithdrawal,
            withdrawal.timestamp,
            ActionsUtils._calcActionId(withdrawal.validator, withdrawal.timestamp),
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
        // no early return past this point, we know that the position will be validated
        isValidated_ = true;

        uint256 available;
        {
            // we calculate the available balance of the vault side at the price of the validate action (ignoring any
            // funding between the initiate and validate)
            int256 vaultAssetAvailable = Vault._vaultAssetAvailable(
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

        uint256 shares = Core._mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);

        // we can add back the _pendingBalanceVault we subtracted in the initiate action
        uint256 tempWithdrawalWithFees =
            Vault._calcBurnUsdn(shares, withdrawal.balanceVault, withdrawal.usdnTotalShares, withdrawal.feeBps);
        s._pendingBalanceVault += tempWithdrawalWithFees.toInt256();

        IUsdn usdn = s._usdn;
        // calculate the amount of asset to transfer with the same fees as recorded during the initiate action
        uint256 assetToTransferWithFees = Vault._calcBurnUsdn(shares, available, usdn.totalShares(), withdrawal.feeBps);

        usdn.burnShares(shares);

        // send the asset to the user
        if (assetToTransferWithFees > 0) {
            s._balanceVault -= assetToTransferWithFees;
            address(s._asset).safeTransfer(withdrawal.to, assetToTransferWithFees);
        }

        emit IUsdnProtocolEvents.ValidatedWithdrawal(
            withdrawal.to,
            withdrawal.validator,
            assetToTransferWithFees,
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
            Core._clearPendingAction(s, pending.validator, rawIndex);
            securityDepositValue_ = pending.securityDepositValue;
            emit IUsdnProtocolEvents.SecurityDepositRefunded(pending.validator, msg.sender, securityDepositValue_);
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
    function _refundExcessEther(uint256 securityDepositValue, uint256 amountToRefund, uint256 balanceBefore) public {
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
    function _refundEther(uint256 amount, address payable to) public {
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
     * @param s The storage of the protocol
     */
    function _checkPendingFee(Types.Storage storage s) public {
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
}
