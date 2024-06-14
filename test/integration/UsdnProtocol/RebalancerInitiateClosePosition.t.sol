// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { MOCK_PYTH_DATA } from "test/unit/Middlewares/utils/Constants.sol";
import { DEPLOYER } from "test/utils/Constants.sol";

import { IRebalancerEvents } from "src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { PositionId, ProtocolAction, TickData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IRebalancerErrors } from "src/interfaces/Rebalancer/IRebalancerErrors.sol";

/**
 * @custom:feature The user rebalancer initiate close position
 * @custom:background A rebalancer is set and the USDN protocol is initialized with the default params
 */
contract UsdnProtocolRebalancerInitiateClosePosition is UsdnProtocolBaseIntegrationFixture, IRebalancerEvents {
    uint256 constant BASE_AMOUNT = 1000 ether;
    uint256 internal securityDepositValue;
    uint128 internal minAsset;
    uint128 internal amountInRebalancer;
    int24 internal tickSpacing;

    PositionId internal posToLiquidate;
    TickData internal tickToLiquidateData;

    function setUp() public {
        (tickSpacing, amountInRebalancer, posToLiquidate, tickToLiquidateData) = _setUpRebalancer();
        skip(5 minutes);

        minAsset = uint128(rebalancer.getMinAssetDeposit());

        mockPyth.setPrice(1280 ether / 1e10);
        mockPyth.setLastPublishTime(block.timestamp);
        assertEq(rebalancer.getPositionVersion(), 0, "rebalancer version should be 0");

        uint256 oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.Liquidation);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA, 1);

        assertEq(rebalancer.getPositionVersion(), 1, "rebalancer version should be updated to 1");
    }

    /**
     * @custom:scenario The user close an amount higher than his rebalancer deposited amount
     * @custom:given A rebalancer long position opened into usdn Protocol
     * @custom:and A deposit user amount invested
     * @custom:when The user call rebalancer `initiateClosePosition`
     * @custom:then The transaction should revert with `RebalancerInvalidAmount`
     */
    function test_RevertWhenRebalancerInvalidAmount() external {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidAmount.selector);
        rebalancer.initiateClosePosition(
            amountInRebalancer + 1, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user close partially with a remaining deposited amount lower than `_minAssetDeposit`
     * @custom:given A rebalancer long position opened into usdn Protocol
     * @custom:and A deposit user amount invested
     * @custom:when The user call rebalancer `initiateClosePosition`
     * @custom:then The transaction should revert with `RebalancerInvalidMinAssetDeposit`
     */
    function test_RevertWhenRebalancerInvalidMinAssetDeposit() external {
        vm.expectRevert(IRebalancerErrors.RebalancerInvalidMinAssetDeposit.selector);
        rebalancer.initiateClosePosition(
            amountInRebalancer - minAsset + 1, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user close partially his deposit amount
     * @custom:given A rebalancer long position opened into usdn Protocol
     * @custom:and A deposit user amount invested
     * @custom:when The user call rebalancer `initiateClosePosition`
     * @custom:then The transaction should be executed
     * @custom:and The user depositData should be updated
     */
    function test_RebalancerInitiateClosePositionPartial() external {
        uint128 amount = amountInRebalancer / 10;

        uint256 amountToClose = FixedPointMathLib.fullMulDiv(
            amount,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );
        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amount, amountToClose, amountInRebalancer - amount);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amount, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "rebalancer close should be successful");

        amountInRebalancer -= amount;

        assertEq(rebalancer.getUserDepositData(address(this)).amount, amountInRebalancer);
        assertEq(rebalancer.getUserDepositData(address(this)).entryPositionVersion, rebalancer.getPositionVersion());
    }

    /**
     * @custom:scenario The user close all his deposit amount
     * @custom:given A rebalancer long position opened into usdn Protocol
     * @custom:and A deposit user amount invested
     * @custom:when The user call rebalancer `initiateClosePosition`
     * @custom:then The transaction should be executed
     * @custom:and The user depositData should be deleted
     */
    function test_RebalancerInitiateClosePosition() external {
        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);

        uint256 amountToClose = FixedPointMathLib.fullMulDiv(
            amountInRebalancer,
            rebalancer.getPositionData(rebalancer.getPositionVersion()).entryAccMultiplier,
            rebalancer.getPositionData(rebalancer.getUserDepositData(address(this)).entryPositionVersion)
                .entryAccMultiplier
        );

        vm.expectEmit();
        emit ClosePositionInitiated(address(this), amountInRebalancer, amountToClose, 0);
        (bool success) = rebalancer.initiateClosePosition{ value: protocol.getSecurityDepositValue() }(
            amountInRebalancer, address(this), payable(address(this)), "", EMPTY_PREVIOUS_DATA
        );

        assertTrue(success, "rebalancer close should be successful");

        assertEq(rebalancer.getUserDepositData(address(this)).amount, 0);
        assertEq(rebalancer.getUserDepositData(address(this)).entryPositionVersion, 0);
    }

    receive() external payable { }
}
