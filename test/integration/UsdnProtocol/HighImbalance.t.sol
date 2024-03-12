// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature A long position is in large bad debt
 * @custom:background This test replicates the transactions observed on a testing fork which resulted in a negative
 * long trading expo. This was due to an erroneous clamping of the balances to remain positive, before any bad debt
 * could be repaid by the vault. The long balance (which was clamped to zero) was thus increased by the amount of the
 * bad debt and became larger than the total expo of the remaining positions. This resulted in a negative trading expo.
 * The fix is now to allow balances to become negative temporarily during calculations.
 */
contract UsdnProtocolHighImbalanceTest is UsdnProtocolBaseIntegrationFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 1 ether;
        params.initialLong = 1 ether;
        params.initialLiqPrice = 1 ether;
        params.initialPrice = 3290 ether;
        params.initialTimestamp = 1_708_088_866; // 16 February 2024 at 14:07 CET
        _setUp(params);
    }

    /**
     * @custom:scenario A very large long position is in large bad debt and gets liquidated
     * @custom:given An initial position of 1 ether with leverage ~1x
     * @custom:when A user try to open a position of 132 ether with leverage ~4.5x
     * @custom:then Transaction should revert with soft imbalance custom error
     */
    function test_RevertWith_highImbalance() public {
        // TODO TO FIX
        vm.skip(true);
        vm.warp(1_708_090_186);
        mockChainlinkOnChain.setLastPublishTime(1_708_090_186 - 10 minutes);
        mockChainlinkOnChain.setLastPrice(3290e8);

        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "USER_1 wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);

        uint256 positionValue = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition);
        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolSoftLongImbalanceLimitReached.selector, int256(2_598_398)
            )
        );
        protocol.initiateOpenPosition{ value: positionValue }(132 ether, 2563 ether, "", "");

        vm.stopPrank();
    }
}
