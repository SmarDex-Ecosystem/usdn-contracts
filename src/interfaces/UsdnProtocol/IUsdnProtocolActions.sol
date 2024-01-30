// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IUsdnProtocolLong } from "src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";

interface IUsdnProtocolActions is IUsdnProtocolLong {
    /**
     * @notice The minimum total supply of USDN that we allow.
     * @dev Upon the first deposit, this amount is sent to the dead address and cannot be later recovered.
     */
    function MIN_USDN_SUPPLY() external view returns (uint256);

    /**
     * @notice Initiate a deposit of assets into the vault to mint USDN.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateDeposit` action.
     * @dev The price validation might require payment according to the return value of the `validationCost` function
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
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @dev The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
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
     * @dev The price validation might require payment according to the return value of the `validationCost` function
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
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @dev The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
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
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @param amount The amount of wstETH to deposit.
     * @param desiredLiqPrice The desired liquidation price.
     * @param currentPriceData  The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @param previousActionPriceData The price data of an actionable pending action.
     * @return tick_ The tick containing the new position
     * @return tickVersion_ The tick version
     * @return index_ The index of the new position inside the tick array
     */
    function initiateOpenPosition(
        uint96 amount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable returns (int24 tick_, uint256 tickVersion_, uint256 index_);

    /**
     * @notice Validate a pending open position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateOpenPosition` action.
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @dev The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
     * @param openPriceData The price data corresponding to the sender's pending open position action.
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function validateOpenPosition(bytes calldata openPriceData, bytes calldata previousActionPriceData)
        external
        payable;

    /**
     * @notice Initiate a close position action.
     * @dev Currently, the `msg.sender` must match the positions' user address.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.InitiateClosePosition` action.
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @dev If the current tick version is greater than the tick version of the position (when it was opened), then the
     * position has been liquidated and the transaction will revert.
     * @param tick The tick containing the position to close
     * @param tickVersion The tick version of the position to close
     * @param index The index of the position inside the tick array
     * @param currentPriceData The current price data
     * @param previousActionPriceData The price data of an actionable pending action.
     */
    function initiateClosePosition(
        int24 tick,
        uint256 tickVersion,
        uint256 index,
        bytes calldata currentPriceData,
        bytes calldata previousActionPriceData
    ) external payable;

    /**
     * @notice Validate a pending close position action.
     * @dev Consult the current oracle middleware implementation to know the expected format for the price data, using
     * the `ProtocolAction.ValidateClosePosition` action.
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @dev The timestamp corresponding to the price data is calculated by adding the mandatory `validationDelay`
     * (from the oracle middleware) to the timestamp of the initiate action.
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
     * @dev The price validation might require payment according to the return value of the `validationCost` function
     * of the middleware.
     * @dev Each tick is liquidated in constant time. The tick version is incremented for each tick that was liquidated.
     * @param currentPriceData The most recent price data
     * @param iterations The maximum number of ticks to liquidate
     * @return liquidated_ The number of ticks that were liquidated
     */
    function liquidate(bytes calldata currentPriceData, uint16 iterations)
        external
        payable
        returns (uint256 liquidated_);
}
