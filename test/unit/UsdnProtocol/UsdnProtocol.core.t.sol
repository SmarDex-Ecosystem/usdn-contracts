// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature The functions of the core of the protocol
 * @custom:background Given a protocol instance that was initialized with 2 longs and 1 short
 */
contract TestUsdnProtocolCore is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check return values of the `funding` function
     * @custom:when The timestamp is the same as the initial timestamp
     * @custom:then The funding should be 0
     */
    function test_funding() public {
        (int256 fund, int256 longExpo, int256 vaultExpo) =
            protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp));
        assertEq(fund, 0, "funding should be 0 if no time has passed");
        assertEq(longExpo, 4.919970269703463156 ether, "longExpo if no time has passed");
        assertEq(vaultExpo, 10 ether, "vaultExpo if no time has passed");
    }

    /**
     * @custom:scenario Calling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimestamp() public {
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(DEFAULT_PARAMS.initialPrice, uint128(DEFAULT_PARAMS.initialTimestamp) - 1);
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
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(DEFAULT_PARAMS.initialPrice / 2));
        uint256 longPosValue = protocol.positionValue(
            DEFAULT_PARAMS.initialPrice, longLiqPrice, DEFAULT_PARAMS.initialLong, initialLongLeverage
        );

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(uint256(protocol.longAssetAvailable(DEFAULT_PARAMS.initialPrice)), longPosValue, "long balance");
    }

    /**
     * @custom:scenario EMA updated correctly
     * @custom:given a negative funding
     * @custom:and an action for a smaller period than the EMA period
     * @custom:then EMA should be greater than the last funding
     */
    function test_updateEma_negFunding() public {
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        // we skip 1 day and call liquidate() to have a negative funding
        skip(1 days);
        protocol.liquidate(priceData, 1);

        int256 lastFunding = protocol.i_lastFunding();
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
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        protocol.initiateOpenPosition(200 ether, DEFAULT_PARAMS.initialPrice / 2, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        int256 lastFunding = protocol.i_lastFunding();
        skip(protocol.getEMAPeriod() - 1);
        // we call liquidate() to update the EMA
        protocol.liquidate(priceData, 1);

        assertLt(protocol.getEMA(), lastFunding);
    }

    /**
     * @custom:scenario Funding calculation
     * @custom:when long and vault expos are equal
     * @custom:then fund should be equal to EMA
     */
    function test_fundingWhenEqualExpo() public {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(20 ether, price / 2, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        // we create a deposit to make the long and vault expos equal
        protocol.initiateDeposit(
            uint128(uint256(protocol.i_longTradingExpo(price) - protocol.i_vaultTradingExpo(price))), priceData, ""
        );
        protocol.validateDeposit(priceData, "");

        assertEq(
            protocol.i_longTradingExpo(price),
            protocol.i_vaultTradingExpo(price),
            "long and vault expos should be equal"
        );
        (int256 fund_,,) = protocol.funding(price, uint128(DEFAULT_PARAMS.initialTimestamp + 60));
        assertEq(fund_, protocol.getEMA(), "funding should be equal to EMA");
    }

    /**
     * @custom:scenario No protocol actions during a greater period than the EMA period
     * @custom:given a non-zero funding
     * @custom:and no actions for a period greater than the EMA period
     * @custom:then EMA should be equal to the last funding
     */
    function test_updateEma_whenTimeGtEMAPeriod() public {
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        // we skip 1 day and call liquidate() to have a non-zero funding
        skip(1 days);
        protocol.liquidate(priceData, 1);

        int256 lastFunding = protocol.i_lastFunding();
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
        // TODO : fix the test when #101 merged
        vm.skip(true);

        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(1000 ether, price * 90 / 100, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        skip(25);
        protocol.liquidate(abi.encode(price / 100), 10);
        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.fundingSF();
        (int256 fund_,,) = protocol.funding(price / 100, uint128(block.timestamp));
        emit log_named_int("fund_", fund_);
        emit log_named_int("mul", -int256(fundingSF) + EMA);
    }
}
