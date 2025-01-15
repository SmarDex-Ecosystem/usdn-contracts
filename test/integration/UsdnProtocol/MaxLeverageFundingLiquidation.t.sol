// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { SET_PROTOCOL_PARAMS_MANAGER } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary } from "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

contract MaxLeverageFundingLiquidation is UsdnProtocolBaseIntegrationFixture {
    uint256 securityDepositValue;
    uint256 lastPrice;
    uint256 adjustedPrice;
    uint256 maxLeverage;
    uint256 maxLeverageLiqPriceWithoutPenalty;
    uint256 longTradingExpo;
    HugeUint.Uint512 accumulator;
    int24 tickSpacing;
    int24 tick;
    uint128 maxLeverageLiqPriceWithPenalty;
    uint256 initialTimestamp;
    bool isInitiated;
    uint256 minLeverage;

    bytes constant MOCK_PYTH_DATA = hex"504e41550000000000000000000000000000000000000000000000000000000011";

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 1002 ether; // needed to trigger rebase
        params.initialLong = 1000 ether;
        _setUp(params);

        (bool success,) = address(wstETH).call{ value: 1000 ether }("");
        require(success, "Could not mint wstETH to USER_1");
        wstETH.approve(address(protocol), type(uint256).max);

        securityDepositValue = protocol.getSecurityDepositValue();
    }

    function test_maxLeverageFundingLiquidation() public {
        lastPrice = protocol.getLastPrice();
        adjustedPrice = lastPrice + lastPrice * protocol.getPositionFeeBps() / UsdnProtocolConstantsLibrary.BPS_DIVISOR;

        maxLeverage = protocol.getMaxLeverage();

        maxLeverageLiqPriceWithoutPenalty =
            adjustedPrice - ((10 ** UsdnProtocolConstantsLibrary.LEVERAGE_DECIMALS * adjustedPrice) / maxLeverage);

        longTradingExpo = protocol.longTradingExpoWithFunding(uint128(block.timestamp), uint128(lastPrice));
        accumulator = protocol.getLiqMultiplierAccumulator();
        tickSpacing = protocol.getTickSpacing();

        tick = protocol.getEffectiveTickForPrice(
            uint128(maxLeverageLiqPriceWithoutPenalty), lastPrice, longTradingExpo, accumulator, tickSpacing
        );

        maxLeverageLiqPriceWithPenalty = protocol.getEffectivePriceForTick(
            tick + int24(protocol.getLiquidationPenalty()), lastPrice, longTradingExpo, accumulator
        );

        initialTimestamp = block.timestamp;

        (isInitiated, /* PositionId memory posId_ */ ) = protocol.initiateOpenPosition{ value: securityDepositValue }(
            2 ether,
            maxLeverageLiqPriceWithPenalty,
            type(uint128).max,
            maxLeverage,
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        assertTrue(isInitiated, "Not initiated");
        minLeverage = protocol.getMinLeverage();

        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setMaxLeverage(minLeverage + 1);

        skip(365 days * 10);

        (uint80 roundId, int256 answer,,,) = mockChainlinkOnChain.latestRoundData();

        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(roundId + 3);

        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;

        mockChainlinkOnChain.setRoundData(
            roundId + 2,
            answer,
            initialTimestamp + oracleMiddleware.getLowLatencyDelay() - 1,
            initialTimestamp + oracleMiddleware.getLowLatencyDelay() - 1,
            roundId + 2
        );
        mockChainlinkOnChain.setRoundData(
            roundId + 3,
            answer,
            initialTimestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1,
            initialTimestamp + oracleMiddleware.getLowLatencyDelay() + protocol.getOnChainValidatorDeadline() + 1,
            roundId + 3
        );

        uint256 validatedActions =
            protocol.validateActionablePendingActions(PreviousActionsData(priceData, rawIndices), 1);

        emit log_named_uint("validatedActions", validatedActions);
    }

    receive() external payable { }
}
