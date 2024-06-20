// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { MockRebalancer } from "../utils/MockRebalancer.sol";
import { ADMIN } from "../../../utils/Constants.sol";

import { ProtocolAction, PositionId } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
     * @custom:scenario
     * @custom:given
     * @custom:when
     * @custom:then
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
