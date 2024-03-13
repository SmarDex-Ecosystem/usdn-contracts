// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized at equilibrium
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 4.919970269703463156 ether; // same as long trading expo
        super._setUp(params);
    }

    /**
     * @custom:scenario Check return values of the `funding` function
     * @custom:when The timestamp is the same as the initial timestamp
     * @custom:then The funding should be 0
     */
    function test_funding() public {
        int256 longExpo = int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong());
        (int256 fund, int256 oldLongExpo) = protocol.funding(uint128(params.initialTimestamp));
        assertEq(fund, 0, "funding should be 0 if no time has passed");
        assertEq(oldLongExpo, longExpo, "longExpo if no time has passed");
    }

    /**
     * @custom:scenario Calling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(uint128(params.initialTimestamp) - 1);
    }

    /**
     * @custom:scenario The long position's value is equal to the long side available balance
     * @custom:given No time has elapsed since the initialization
     * @custom:and The price of the asset is equal to the initial price
     * @custom:then The long side available balance is equal to the first position value
     * @dev Due to imprecision in the calculations, there are in practice a few wei of difference, but always in favor
     * of the protocol (see fuzzing tests)
     */
    function test_longAssetAvailable() public {
        // calculate the value of the deployer's long position
        uint128 longLiqPrice =
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(params.initialPrice / 2));
        uint256 longPosValue = protocol.i_positionValue(params.initialPrice, longLiqPrice, initialLongExpo);

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(uint256(protocol.i_longAssetAvailable(params.initialPrice)), longPosValue, "long balance");
    }

    /**
     * @custom:scenario EMA updated correctly
     * @custom:given a negative funding
     * @custom:and an action for a smaller period than the EMA period
     * @custom:then EMA should be greater than the last funding
     */
    function test_updateEma_negFunding() public {
        // we create a deposit and skip 1 day and call liquidate() to have a negative funding
        bytes memory priceData = abi.encode(params.initialPrice);
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 10 ether, params.initialPrice);
        skip(1 days);
        protocol.liquidate(priceData, 1);

        int256 lastFunding = protocol.getLastFunding();
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.liquidate(priceData, 1);

        assertGt(protocol.getEMA(), lastFunding);
    }

    /**
     * @custom:scenario EMA updated correctly
     * @custom:given a positive funding
     * @custom:and an action for a smaller period than the EMA period
     * @custom:then EMA should be lower than the last funding
     */
    function test_updateEma_posFunding() public {
        setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 200 ether, params.initialPrice / 2, params.initialPrice
        );

        int256 lastFunding = protocol.getLastFunding();
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.liquidate(abi.encode(params.initialPrice), 1);

        assertLt(protocol.getEMA(), lastFunding);
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when long and vault expos are equal
     * @custom:then fund should be equal to EMA
     */
    function test_fundingWhenEqualExpo() public {
        assertEq(
            protocol.i_longTradingExpo(params.initialPrice),
            protocol.i_vaultTradingExpo(params.initialPrice),
            "long and vault expos should be equal"
        );
        (int256 fund_, int256 oldLongExpo) = protocol.funding(uint128(params.initialTimestamp + 60));
        assertEq(fund_, protocol.getEMA(), "funding should be equal to EMA");
        assertEq(
            oldLongExpo,
            int256(protocol.getTotalExpo() - protocol.getBalanceLong()),
            "old long expo should be the same as last update"
        );
    }

    /**
     * @custom:scenario No protocol actions during a greater period than the EMA period
     * @custom:given a non-zero funding
     * @custom:and no actions for a period greater than the EMA period
     * @custom:then EMA should be equal to the last funding
     */
    function test_updateEma_whenTimeGtEMAPeriod() public {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        bytes memory priceData = abi.encode(params.initialPrice);
        // we skip 1 day and call liquidate() to have a non-zero funding
        skip(1 days);
        protocol.liquidate(priceData, 1);

        int256 lastFunding = protocol.getLastFunding();
        skip(protocol.getEMAPeriod() + 1);
        // we call liquidate() to update the EMA
        protocol.liquidate(priceData, 1);

        assertEq(protocol.getEMA(), lastFunding, "EMA should be equal to last funding");
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when the long expo is negative
     * @custom:and the vault expo is zero
     * @custom:then fund should be equal to -fundingSF + EMA
     */
    function test_funding_NegLong_ZeroVault() public {
        skip(1 hours);
        uint128 price = params.initialPrice;
        setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1000 ether, price * 90 / 100, price);

        skip(1 hours);
        protocol.liquidate(abi.encode(price / 100), 10);
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (int256 fund_,) = protocol.funding(uint128(block.timestamp));

        assertEq(fund_, -int256(fundingSF) + EMA, "funding should be equal to -fundingSF + EMA");
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when the long expo is positive
     * @custom:and the vault expo is zero
     * @custom:then fund should be equal to fundingSF + EMA
     */
    function test_funding_PosLong_ZeroVault() public {
        skip(1 hours);
        uint128 price = params.initialPrice;
        setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1000 ether, price * 90 / 100, price);

        skip(1 hours);
        protocol.liquidate(abi.encode(price * 100), 10);
        assertGt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be positive");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (int256 fund_,) = protocol.funding(uint128(block.timestamp));

        assertEq(fund_, int256(fundingSF) + EMA, "funding should be equal to fundingSF + EMA");
    }
}
