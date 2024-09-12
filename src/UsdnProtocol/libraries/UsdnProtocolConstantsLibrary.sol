// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library UsdnProtocolConstantsLibrary {
    uint8 internal constant LEVERAGE_DECIMALS = 21;
    uint8 internal constant FUNDING_RATE_DECIMALS = 18;
    uint8 internal constant TOKENS_DECIMALS = 18;
    uint8 internal constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;
    uint8 internal constant FUNDING_SF_DECIMALS = 3;
    uint256 internal constant SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint16 internal constant MAX_LIQUIDATION_ITERATION = 10;
    int24 internal constant NO_POSITION_TICK = type(int24).min;
    address internal constant DEAD_ADDRESS = address(0xdead);
    uint256 internal constant MIN_USDN_SUPPLY = 1000;
    uint256 internal constant MIN_INIT_DEPOSIT = 1 ether;
    uint256 internal constant MAX_ACTIONABLE_PENDING_ACTIONS = 20;
    uint256 internal constant MIN_VALIDATION_DEADLINE = 60;
    uint256 internal constant MAX_VALIDATION_DEADLINE = 1 days;
    uint256 internal constant MAX_LIQUIDATION_PENALTY = 1500;
    uint256 internal constant MAX_SAFETY_MARGIN_BPS = 2000;
    uint256 internal constant MAX_EMA_PERIOD = 90 days;
    uint256 internal constant MAX_POSITION_FEE_BPS = 2000;
    uint256 internal constant MAX_VAULT_FEE_BPS = 2000;
    uint256 internal constant MAX_LEVERAGE = 100 * 10 ** LEVERAGE_DECIMALS;

    // After some checks, 1% would mean a user with a position with 10x leverage needs the price to 900x before it
    // limits the position's PnL. We think it's unlikely enough so we don't consider it a problem
    uint256 internal constant MIN_LONG_TRADING_EXPO_BPS = 100;
}
