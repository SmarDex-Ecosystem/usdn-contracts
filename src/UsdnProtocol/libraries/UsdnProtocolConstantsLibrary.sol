// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

library UsdnProtocolConstantsLibrary {
    uint8 constant LEVERAGE_DECIMALS = 21;
    uint8 constant FUNDING_RATE_DECIMALS = 18;
    uint8 constant TOKENS_DECIMALS = 18;
    uint8 constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;
    uint8 constant FUNDING_SF_DECIMALS = 3;
    uint256 constant SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;
    uint256 constant BPS_DIVISOR = 10_000;
    uint16 constant MAX_LIQUIDATION_ITERATION = 10;
    int24 constant NO_POSITION_TICK = type(int24).min;
    address constant DEAD_ADDRESS = address(0xdead);
    uint256 constant MIN_USDN_SUPPLY = 1000;
    uint256 constant MIN_INIT_DEPOSIT = 1 ether;
    uint256 internal constant MAX_ACTIONABLE_PENDING_ACTIONS = 20;
}
