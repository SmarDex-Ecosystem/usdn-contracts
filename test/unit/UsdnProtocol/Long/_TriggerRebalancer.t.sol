// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { MockRebalancer } from "../utils/MockRebalancer.sol";

import { PositionId, ProtocolAction } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature the _triggerRebalancer internal function of the UsdnProtocolLong contract
contract TestUsdnProtocolLongTriggerRebalancer is UsdnProtocolBaseFixture {
    MockRebalancer mockedRebalancer;

    uint256 longBalance = DEFAULT_PARAMS.initialLong;
    uint256 vaultBalance = DEFAULT_PARAMS.initialDeposit;
    uint128 lastPrice = DEFAULT_PARAMS.initialPrice;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableRebalancer = true;
        super._setUp(params);

        mockedRebalancer = new MockRebalancer();

        vm.prank(ADMIN);
        protocol.setRebalancer(mockedRebalancer);
    }

    /**
     * @custom:scenario The rebalancer is triggered but with no new position and 0 value in the previous position
     * @custom:given A rebalancer that was already triggered and has a position
     * @custom:when The rebalancer is triggered again
     * @custom:and There is no pending assets
     * @custom:and The value of the existing position is 10_000 wei
     * @custom:then The position value is gifted to the vault
     * @custom:and The position is closed
     * @custom:and no new position is opened
     */
    function test_triggerRebalancerWithNoPendingAssetsAndLowPosValue() public {
        int256 remainingCollateral = 1 ether;
        uint8 assetDecimals = protocol.getAssetDecimals();
        uint128 amount = 10_000;

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(mockedRebalancer),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: amount,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 2,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        mockedRebalancer.setCurrentStateData(0, protocol.getMaxLeverage(), posId);

        vm.prank(ADMIN);
        protocol.setMinLongPosition(10 ** assetDecimals);

        (uint256 newLongBalance, uint256 newVaultBalance) =
            protocol.i_triggerRebalancer(lastPrice, longBalance, vaultBalance, remainingCollateral);

        assertEq(newLongBalance, longBalance - amount + 1, "");
        assertEq(newVaultBalance, vaultBalance + amount - 1, "");
    }
}
