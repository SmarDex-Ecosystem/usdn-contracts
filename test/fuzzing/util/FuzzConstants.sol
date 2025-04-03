// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/*
 * Using constants since we can't read from env
 */
contract FuzzConstants {
    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    bytes32 internal constant PYTH_FEED_ID = 0x0000000000000000000000000000000000000000000000000000000000000001;
    uint256 CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;

    uint256 internal constant INIT_DEPOSIT_AMOUNT = 2e18;
    uint256 internal constant INIT_LONG_AMOUNT = 2e18;

    int256 internal constant INT_ONE_HUNDRED_BP = 10_000;
    int256 constant INT_ONE_PERCENT_BP = 100;
    int256 internal constant INT_MAX_CHANGE_BP = 2000;
    int256 internal constant MIN_ORACLE_PRICE = 500; // USD

    int256 constant SWING_MODE_NORMAL_MAX_CHANGE = 3 * INT_ONE_PERCENT_BP; // 3%
    int256 constant SWING_MODE_LARGE_MAX_CHANGE = 10 * INT_ONE_PERCENT_BP; // 10%
}
