// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";

import { FeeCollector } from "../../../../src/utils/FeeCollector.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The callback function of the `FeeCollector` contract
 * @custom:background Given a `FeeCollector` contract
 */
contract TestFeeCollectorCallback is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        params.flags.enableProtocolFees = true;
        super._setUp(params);
    }

    /**
     * @custom:scenario Check that the protocol is calling the callback function
     * of the fee collector after that the threshold is reached
     * @custom:given The pending protocol fee is 0
     * @custom:when Multiple actions are performed to reach the fee threshold
     * @custom:then The callback function of the fee collector is called
     */
    function test_callback() public {
        address feeCollectorWithCallback = address(new FeeCollectorWithCallback());
        vm.prank(ADMIN);
        protocol.setFeeCollector(feeCollectorWithCallback);
        assertEq(protocol.getFeeCollector(), feeCollectorWithCallback);

        setUpUserPositionInVault(
            address(this), ProtocolAction.ValidateDeposit, 10_000 ether, DEFAULT_PARAMS.initialPrice
        );
        skip(30 days);

        assertEq(wstETH.balanceOf(address(feeCollectorWithCallback)), 0, "fee collector balance before collect");
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, DEFAULT_PARAMS.initialPrice);

        assertGe(
            wstETH.balanceOf(address(feeCollectorWithCallback)),
            protocol.getFeeThreshold(),
            "fee collector balance after collect"
        );
        assertEq(FeeCollectorWithCallback(feeCollectorWithCallback).called(), true, "fee collector callback called");
    }
}

contract FeeCollectorWithCallback is FeeCollector {
    bool public called;

    function feeCollectorCallback(uint256 feeAmount) external override {
        feeAmount;
        called = true;
    }
}
