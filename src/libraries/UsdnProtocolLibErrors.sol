// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @dev Indicates that the liquidation price is higher than or equal to the start price
error UsdnProtocolLibInvalidLiquidationPrice(uint128 liquidationPrice, uint128 startPrice);

/// @dev Indicates that the provided timestamp is too old (pre-dates the last balances update)
error UsdnProtocolLibLeverageTooLow();

/// @dev Indicates that the provided collateral and liquidation price result in a leverage that is too low
error UsdnProtocolLibLeverageTooHigh();
