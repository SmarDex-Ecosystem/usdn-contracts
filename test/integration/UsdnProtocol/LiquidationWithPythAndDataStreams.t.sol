// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";

/**
 * @custom:feature Liquidation with Pyth and Chainlink data streams.
 * @custom:background A initiated USDN protocol.
 */
contract TestLiquidationWithPythAndDataStreams is UsdnProtocolBaseIntegrationFixture {
    int24 tick;
    uint256 initialTickVersion;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        tick = protocol.getHighestPopulatedTick();
        initialTickVersion = protocol.getTickVersion(tick);

        skip(1 minutes);
    }

    /**
     * @custom:scenario Tests the `liquidate` function with a Chainlink data streams price.
     * @custom:given A position with a liquidation tick above the current price.
     * @custom:when The function is called.
     * @custom:then The tick must be liquidated.
     */
    function test_liquidateWithDataStreams() external {
        report.validFromTimestamp = uint32(block.timestamp);
        report.observationsTimestamp = uint32(block.timestamp);
        report.price = int192(int128(params.initialLiqPrice)) / 2;
        (, payload) = _encodeReport(report);

        uint256 dataStreamFee = oracleMiddleware.validationCost(payload, ProtocolAction.Liquidation);
        protocol.liquidate{ value: dataStreamFee }(payload);
        assertGt(protocol.getTickVersion(tick), initialTickVersion, "Tick must be liquidated with Data streams");
    }

    /**
     * @custom:scenario Tests the `liquidate` function with a Pyth price.
     * @custom:given A position with a liquidation tick above the current price.
     * @custom:when The function is called.
     * @custom:then The tick must be liquidated.
     */
    function test_liquidateWithPyth() external {
        mockPyth.setPrice(int64(int128(params.initialLiqPrice)) / 2 / 1e10);
        mockPyth.setLastPublishTime(block.timestamp);

        uint256 pythFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: pythFee }(MOCK_PYTH_DATA);
        assertGt(protocol.getTickVersion(tick), initialTickVersion, "Tick must be liquidated with Pyth");
    }
}
