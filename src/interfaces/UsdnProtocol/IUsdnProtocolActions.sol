// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";

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
     * @param amount The amount of wstETH to deposit.
     * @param currentPriceData The current price data
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function initiateDeposit(uint128 amount, bytes calldata currentPriceData, bytes calldata previousActionPriceData)
        external
        payable;

    /**
     * @notice Validate a pending deposit action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateDeposit` action.
     * The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * @param depositPriceData The price data corresponding to the sender's pending deposit action.
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function validateDeposit(bytes calldata depositPriceData, bytes calldata previousActionPriceData)
        external
        payable;

    /**
     * @notice Initiate a withdrawal of assets from the vault by providing USDN tokens.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * @param usdnAmount The amount of USDN to burn.
     * @param currentPriceData The current price data
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function initiateWithdrawal(
        uint128 usdnAmount,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable;

    /**
     * @notice Validate a pending withdrawal action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateWithdrawal` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function
     * of the middleware.
     * The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * @param withdrawalPriceData The price data corresponding to the sender's pending withdrawal action.
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function validateWithdrawal(bytes calldata withdrawalPriceData, bytes calldata previousActionPriceData)
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
     * @param amount The amount of wstETH to deposit.
     * @param desiredLiqPrice The desired liquidation price, including the liquidation penalty.
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @param previousActionPriceData The price data of an actionable pending action.
     * @return tick_ The tick containing the new position
     * @return tickVersion_ The tick version
     * @return index_ The index of the new position inside the tick array
     */
    function initiateOpenPosition(
        uint128 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable returns (int24 tick_, uint256 tickVersion_, uint256 index_);

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
     * @param openPriceData The price data corresponding to the sender's pending open position action.
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function validateOpenPosition(bytes calldata openPriceData, bytes calldata previousActionPriceData)
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
     * @param tick The tick containing the position to close
     * @param tickVersion The tick version of the position to close
     * @param index The index of the position inside the tick array
     * @param amountToClose The amount of collateral to remove from the position's amount
     * @param currentPriceData The current price data
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function initiateClosePosition(
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        uint128 amountToClose,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
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
     * @param closePriceData The price data corresponding to the sender's pending close position action.
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function validateClosePosition(bytes calldata closePriceData, bytes calldata previousActionPriceData)
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
}
