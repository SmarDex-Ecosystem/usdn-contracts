// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

contract TestUsdnProtocolMaxMaxLeverage is UsdnProtocolBaseFixture {
    uint256 internal constant LONG_AMOUNT = 4 ether;
    uint128 internal constant CURRENT_PRICE = 3000 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = CURRENT_PRICE;
        params.initialLong = 360 ether;
        params.initialDeposit = 375 ether;
        params.flags.enableLimits = true;
        params.flags.enableLiqPenalty = false;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 10 ether, address(protocol), type(uint256).max);
    }

    function test_maxMaxLeverageWithoutCheck() public {
        // leverage approx 10x
        (, PositionId memory posId) = protocol.initiateOpenPosition(
            uint128(LONG_AMOUNT),
            CURRENT_PRICE * 9 / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(CURRENT_PRICE),
            EMPTY_PREVIOUS_DATA
        );

        (Position memory pos,) = protocol.getLongPosition(posId);
        emit log_named_decimal_uint(
            "initial leverage",
            pos.totalExpo * 10 ** Constants.LEVERAGE_DECIMALS / pos.amount,
            Constants.LEVERAGE_DECIMALS
        );

        _waitDelay();

        uint128 validatePrice = CURRENT_PRICE * 9 / 10;
        uint128 liqPrice = protocol.getEffectivePriceForTick(
            posId.tick + 100,
            validatePrice,
            protocol.longTradingExpoWithFunding(validatePrice, uint128(block.timestamp - 1)),
            protocol.getLiqMultiplierAccumulator()
        );
        liqPrice = protocol.getEffectivePriceForTick(
            posId.tick + 100,
            liqPrice,
            protocol.longTradingExpoWithFunding(liqPrice, uint128(block.timestamp - 1)),
            protocol.getLiqMultiplierAccumulator()
        );
        emit log_named_decimal_uint(
            "pos liq price",
            protocol.getEffectivePriceForTick(
                posId.tick,
                liqPrice,
                protocol.longTradingExpoWithFunding(liqPrice, uint128(block.timestamp - 1)),
                protocol.getLiqMultiplierAccumulator()
            ),
            18
        );
        emit log_named_decimal_uint("validate price", liqPrice, 18);
        (, PositionId memory newPosId) =
            protocol.validateOpenPosition(payable(address(this)), abi.encode(liqPrice), EMPTY_PREVIOUS_DATA);

        (pos,) = protocol.getLongPosition(newPosId);
        emit log_named_decimal_uint(
            "final leverage",
            pos.totalExpo * 10 ** Constants.LEVERAGE_DECIMALS / pos.amount,
            Constants.LEVERAGE_DECIMALS
        );

        uint256 vaultTradingExpo = protocol.vaultAssetAvailableWithFunding(liqPrice, uint128(block.timestamp - 1));
        emit log_named_decimal_uint("vault trading expo", vaultTradingExpo, 18);
        uint256 longTradingExpo = protocol.longTradingExpoWithFunding(liqPrice, uint128(block.timestamp - 1));
        emit log_named_decimal_uint("long trading expo", longTradingExpo, 18);
        int256 denominator = int256(longTradingExpo);
        if (int256(vaultTradingExpo) > denominator) {
            denominator = int256(vaultTradingExpo);
        }
        int256 imbalance = (int256(longTradingExpo) - int256(vaultTradingExpo)) * 1e18 * 100 / denominator;
        emit log_named_decimal_int("imbalance %", imbalance, 18);
    }
}
