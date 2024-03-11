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
        int256 longExpo = int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong());
        (int256 fund, int256 oldLongExpo) =
            protocol.funding(uint128(DEFAULT_PARAMS.initialTimestamp), protocol.getEMA());
        assertEq(fund, 0, "funding should be 0 if no time has passed");
        assertEq(oldLongExpo, longExpo, "longExpo if no time has passed");
    }

    /**
     * @custom:scenario Calling the `funding` function
     * @custom:when The timestamp is in the past
     * @custom:then The protocol reverts with `UsdnProtocolTimestampTooOld`
     */
    function test_RevertWhen_funding_pastTimestamp() public {
        int256 ema = protocol.getEMA();
        vm.expectRevert(UsdnProtocolTimestampTooOld.selector);
        protocol.funding(uint128(DEFAULT_PARAMS.initialTimestamp) - 1, ema);
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
        uint256 longPosValue = protocol.i_positionValue(DEFAULT_PARAMS.initialPrice, longLiqPrice, initialLongExpo);

        // there are rounding errors when calculating the value of a position, here we have up to 1 wei of error for
        // each position, but always in favor of the protocol.
        assertGe(uint256(protocol.i_longAssetAvailable(DEFAULT_PARAMS.initialPrice)), longPosValue, "long balance");
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
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
        protocol.initiateOpenPosition(200 ether, DEFAULT_PARAMS.initialPrice / 2, priceData, "");
        protocol.validateOpenPosition(priceData, "");

        int256 lastFunding = protocol.getLastFunding();
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

        int256 EMA = protocol.getEMA();
        (int256 fund_, int256 oldLongExpo) = protocol.funding(uint128(DEFAULT_PARAMS.initialTimestamp + 60), EMA);
        assertEq(fund_, EMA, "funding should be equal to EMA");
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
        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);
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
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(1000 ether, price * 90 / 100, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");

        skip(1 hours);
        protocol.liquidate(abi.encode(price / 100), 10);
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (int256 fund_,) = protocol.funding(uint128(block.timestamp), EMA);

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
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(1000 ether, price * 90 / 100, priceData, "");
        skip(oracleMiddleware.getValidationDelay() + 1);
        protocol.validateOpenPosition(priceData, "");

        skip(1 hours);
        protocol.liquidate(abi.encode(price * 100), 10);
        assertGt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be positive");
        assertEq(protocol.getBalanceVault(), 0, "vault expo should be zero");

        int256 EMA = protocol.getEMA();
        uint256 fundingSF = protocol.getFundingSF();
        (int256 fund_,) = protocol.funding(uint128(block.timestamp), EMA);

        assertEq(fund_, int256(fundingSF) + EMA, "funding should be equal to fundingSF + EMA");
    }

    /**
     * @custom:scenario longAssetAvailableWithFundingAndFees calculation
     * @custom:when the funding is positive
     * @custom:then return value should be equal to the long balance
     */
    function test_longAssetAvailableWithFundingAndFees_posFund() public {
        skip(1 hours);
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(1 ether, price * 90 / 100, priceData, "");
        _waitDelay();
        protocol.validateOpenPosition(priceData, "");
        skip(1 hours);

        (int256 fund,) = protocol.funding(uint128(block.timestamp), protocol.getEMA());
        assertGt(fund, 0, "funding should be positive");

        int256 available = protocol.longAssetAvailableWithFundingAndFees(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.liquidate(priceData, 5);
        assertEq(available, int256(protocol.getBalanceLong()), "long balance != available");
    }

    /**
     * @custom:scenario longAssetAvailableWithFundingAndFees calculation
     * @custom:when the funding is negative
     * @custom:then return value should be equal to the long balance
     */
    function test_longAssetAvailableWithFundingAndFees_negFund() public {
        skip(1 hours);
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;

        (int256 fund,) = protocol.funding(uint128(block.timestamp), protocol.getEMA());
        assertLt(fund, 0, "funding should be negative");

        int256 available = protocol.longAssetAvailableWithFundingAndFees(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.liquidate(abi.encode(price), 5);
        assertEq(available, int256(protocol.getBalanceLong()), "long balance != available");
    }

    /**
     * @custom:scenario vaultAssetAvailableWithFundingAndFees calculation
     * @custom:when the funding is negative
     * @custom:then return value should be equal to the vault balance
     */
    function test_vaultAssetAvailableWithFundingAndFees_negFund() public {
        skip(1 hours);
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;

        (int256 fund,) = protocol.funding(uint128(block.timestamp), protocol.getEMA());
        assertLt(fund, 0, "funding should be negative");

        int256 available = protocol.vaultAssetAvailableWithFundingAndFees(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.liquidate(abi.encode(price), 5);
        assertEq(available, int256(protocol.getBalanceVault()), "vault balance != available");
    }

    /**
     * @custom:scenario vaultAssetAvailableWithFundingAndFees calculation
     * @custom:when the funding is positive
     * @custom:then return value should be equal to the vault balance
     */
    function test_vaultAssetAvailableWithFundingAndFees_posFund() public {
        skip(1 hours);
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
        uint128 price = DEFAULT_PARAMS.initialPrice;
        bytes memory priceData = abi.encode(price);

        protocol.initiateOpenPosition(1 ether, price * 90 / 100, priceData, "");
        _waitDelay();
        protocol.validateOpenPosition(priceData, "");
        skip(1 hours);

        (int256 fund,) = protocol.funding(uint128(block.timestamp), protocol.getEMA());
        assertGt(fund, 0, "funding should be positive");

        int256 available = protocol.vaultAssetAvailableWithFundingAndFees(price, uint128(block.timestamp) - 30);
        // call liquidate to update the contract state
        protocol.liquidate(priceData, 5);
        assertEq(available, int256(protocol.getBalanceVault()), "vault balance != available");
    }
}
