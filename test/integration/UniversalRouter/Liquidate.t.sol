// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { PYTH_ETH_USD } from "test/utils/Constants.sol";

/**
 * @custom:feature Test liquidate command of universal router
 * @custom:background A initiated universal router
 */
contract TestForkUniversalRouterLiquidate is UniversalRouterBaseFixture {
    function setUp() external {
        _setUp();
    }

    /**
     * @custom:scenario Test the `LIQUIDATE`command of the universal router
     * @custom:given A initiated universal router
     * @custom:and A recent pyth price
     * @custom:when The command is executed
     * @custom:then The transaction should be executed
     */
    function test_ForkExecuteLiquidate() external {
        bytes memory commands = abi.encodePacked(uint8(Commands.LIQUIDATE));
        (,,,, bytes memory data) = getHermesApiSignature(PYTH_ETH_USD, block.timestamp);
        uint256 validationCost = oracleMiddleware.validationCost(data, ProtocolAction.Liquidation);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(data, 10, validationCost);
        router.execute{ value: validationCost }(commands, inputs);
    }
}
