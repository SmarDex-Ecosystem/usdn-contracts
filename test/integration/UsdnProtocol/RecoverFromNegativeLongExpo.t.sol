// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature This test restores balance to a protocol with a negative long expo
 * @custom:background In the event of a negative long expo, the protocol blocks deposit and close actions to prevent the
 * expo imbalance from worsening, but allows open and withdrawal to help restore a positive expo
 */
contract RecoverFromNegativeLongExpoTest is UsdnProtocolBaseIntegrationFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:given A initial balanced protocol
     * @custom:and A user long position is initiated
     * @custom:and Price drop below all liquidation price
     * @custom:and The user position trying to be validated
     * @custom:and Protocol goes with a negative long expo
     * @custom:when A user open a long position
     * @custom:then Protocol should recover a positive long expo
     */
    function test_RecoverFromNegativeLongExpo() public {
        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "Recover negative long expo: wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);

        protocol.initiateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, params.initialLiqPrice + (params.initialLiqPrice * 2 / 10), "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        mockPyth.setPrice(
            int64(
                int256(
                    uint256(params.initialLiqPrice)
                        / 10 ** (protocol.getAssetDecimals() - uint256(-int256(mockPyth.expo()))) / 2
                )
            )
        );

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }("beef", EMPTY_PREVIOUS_DATA);

        // long expo should be negative
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");

        uint128 currentPrice = uint128(
            uint256(uint64(mockPyth.price())) * 10 ** (protocol.getAssetDecimals() - uint256(-int256(mockPyth.expo())))
        );

        protocol.initiateOpenPosition{ value: oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition) }(
            1 ether, currentPrice / 2, "", EMPTY_PREVIOUS_DATA
        );

        // long expo should be positive
        assertTrue(
            int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()) > 0, "long expo should be positive"
        );
        vm.stopPrank();
    }
}
