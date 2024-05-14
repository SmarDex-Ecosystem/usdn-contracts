// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { PreviousActionsData, PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

interface IUsdnProtocolActions is IUsdnProtocolLong {
    /**
     * @notice The minimum total supply of USDN that we allow.
     * @dev Upon the first deposit, this amount is sent to the dead address and cannot be later recovered.
     */
    function MIN_USDN_SUPPLY() external pure returns (uint256);

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The transaction must have _securityDepositValue in value.
     * @param amount The amount of wstETH to deposit.
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param to The address that will receive the USDN tokens
     */
    function initiateDeposit(
        uint128 amount,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable;

    /**
     * @notice Validate a pending deposit action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateDeposit` action.
     * The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * The security deposit will be returned to the sender.
     * @param depositPriceData The price data corresponding to the sender's pending deposit action.
     * @param previousActionsData The data needed to validate actionable pending actions.
     */
    function validateDeposit(bytes calldata depositPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The transaction must have _securityDepositValue in value.
     * @param usdnShares The amount of USDN shares to burn (Max 5708990770823839524233143877797980545530986495 which is
     * equivalent to 5.7B USDN token before any rebase. The token amount limit increases with each rebase)
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param to The address that will receive the assets
     */
    function initiateWithdrawal(
        uint152 usdnShares,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable;

    /**
     * @notice Validate a pending withdrawal action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * The security deposit will be returned to the sender.
     * @param withdrawalPriceData The price data corresponding to the sender's pending withdrawal action.
     * @param previousActionsData The data needed to validate actionable pending actions.
     */
    function validateWithdrawal(bytes calldata withdrawalPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;

    /**
     * @notice Initiate an open position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateOpenPosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The position is immediately included in the protocol calculations with a temporary entry price (and thus
     * leverage). The validation operation then updates the entry price and leverage with fresher data.
     * The transaction must have _securityDepositValue in value.
     * @param amount The amount of wstETH to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param to The address that will be the owner of the position
     * @return posId_ The unique position identifier
     */
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable returns (PositionId memory posId_);

    /**
     * @notice Validate a pending open position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateOpenPosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * This operation adjusts the entry price and initial leverage of the position.
     * It is also possible for this operation to change the tick, tickVersion and index of the position, in which case
     * we emit the `LiquidationPriceUpdated` event.
     * The security deposit will be returned to the sender.
     * @param openPriceData The price data corresponding to the sender's pending open position action.
     * @param previousActionsData The data needed to validate actionable pending actions.
     */
    function validateOpenPosition(bytes calldata openPriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;

    /**
     * @notice Initiate a close position action.
     * @dev Currently, the `msg.sender` must match the positions' user address.
     * Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and the transaction will revert.
     * The appropriate amount and total expo are taken out of the tick and put in a pending state during this operation.
     * Thus, calculations don't consider those anymore. The exit price (and thus profit) is not yet set definitively,
     * and will be done during the validate action.
     * The transaction must have _securityDepositValue in value.
     * @param posId The unique identifier of the position to close
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param to The address that will receive the assets
     */
    function initiateClosePosition(
        PositionId calldata posId,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        PreviousActionsData calldata previousActionsData,
        address to
    ) external payable;

    /**
     * @notice Validate a pending close position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateClosePosition` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * This operation calculates the final exit price and profit of the long position and performs the payout.
     * The security deposit will be returned to the sender.
     * @param closePriceData The price data corresponding to the sender's pending close position action.
     * @param previousActionsData The data needed to validate actionable pending actions.
     */
    function validateClosePosition(bytes calldata closePriceData, PreviousActionsData calldata previousActionsData)
        external
        payable;

    /**
     * @notice Liquidate positions according to the current asset price, limited to a maximum of `iterations` ticks.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.Liquidation` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * Each tick is liquidated in constant time. The tick version is incremented for each tick that was liquidated.
     * At least one tick will be liquidated, even if the `iterations` parameter is zero.
     * @param currentPriceData The most recent price data
     * @param iterations The maximum number of ticks to liquidate
     * @return liquidatedPositions_ The number of positions that were liquidated
     */
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidatedPositions_);

    /**
     * @notice Manually validate one or more actionable pending actions.
     * @dev The price validation might require payment according to the return value of the `getValidationCost`
     * function of the middleware.
     * The timestamp for the price data of each actionable pending action is calculated by adding the mandatory
     * `validationDelay` (from the oracle middleware) to the timestamp of the pending action.
     * @param previousActionsData The data needed to validate actionable pending actions.
     * @param maxValidations The maximum number of actionable pending actions to validate. Even if zero, at least one
     * validation will be performed.
     * @return validatedActions_ The number of validated actionable pending actions.
     */
    function validateActionablePendingActions(PreviousActionsData calldata previousActionsData, uint256 maxValidations)
        external
        payable
        returns (uint256 validatedActions_);
}
