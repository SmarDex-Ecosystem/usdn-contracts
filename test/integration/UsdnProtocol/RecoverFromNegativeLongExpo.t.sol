// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";

import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER, USER_1, USER_2 } from "test/utils/Constants.sol";

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
        // both price oracle should be equal
        (, int256 answer,,,) = mockChainlinkOnChain.latestRoundData();
        assertEq(int256(mockPyth.price()), answer);

        vm.startPrank(USER_1);
        wstETH.mintAndApprove(USER_1, 200 ether, address(protocol), type(uint256).max);

        uint256 assetDecimals = uint256(uint8(protocol.getAssetDecimals()));
        uint256 pythDecimals = uint256(-int256(mockPyth.expo()));

        uint128 initialPrice = _getAdjustedPrice(uint256(uint64(mockPyth.price())), pythDecimals, assetDecimals);

        uint256 minLongValue = uint256(protocol.getMinLongPosition());
        uint128 minLongAmount = uint128(minLongValue * (10 ** assetDecimals) / initialPrice);
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 initiateValidationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition);

        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmount, params.initialLiqPrice + (params.initialLiqPrice * 2 / 10), "beef", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        uint256 adjustedLowMockPythPrice = _getAdjustedPrice(params.initialLiqPrice / 2, assetDecimals, pythDecimals);

        mockPyth.setPrice(int64(int256(adjustedLowMockPythPrice)));
        mockPyth.setLastPublishTime(block.timestamp);
        mockChainlinkOnChain.setLastPrice(int256(adjustedLowMockPythPrice));
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }("beef", EMPTY_PREVIOUS_DATA);

        // long expo should be negative
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");

        uint128 priceDown = _getAdjustedPrice(uint256(uint64(mockPyth.price())), pythDecimals, assetDecimals);

        uint128 minLongAmountDown = uint128(minLongValue * (10 ** assetDecimals) / priceDown);

        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmountDown, priceDown / 2, "beef", EMPTY_PREVIOUS_DATA
        );

        // long expo should be positive
        assertTrue(
            int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()) > 0, "long expo should be positive"
        );

        vm.stopPrank();
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
    function test_RecoverFromNegativeLongExpoAndZeroVaultExpo() public {
        vm.prank(DEPLOYER);
        protocol.setPositionFeeBps(0);

        // both price oracle should be equal
        (, int256 answer,,,) = mockChainlinkOnChain.latestRoundData();
        assertEq(int256(mockPyth.price()), answer);

        uint256 assetDecimals = uint256(uint8(protocol.getAssetDecimals()));
        uint256 pythDecimals = uint256(-int256(mockPyth.expo()));
        uint128 initialPrice = _getAdjustedPrice(uint256(uint64(mockPyth.price())), pythDecimals, assetDecimals);
        uint256 minLongPosition = uint256(protocol.getMinLongPosition());
        uint128 minWstethAmount = uint128(minLongPosition * (10 ** assetDecimals) / initialPrice);
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 initiateOpenValidationCost =
            oracleMiddleware.validationCost("beef", ProtocolAction.InitiateOpenPosition);
        uint256 initiateDepositValidationCost = oracleMiddleware.validationCost("beef", ProtocolAction.InitiateDeposit);

        vm.startPrank(USER_1);
        wstETH.mintAndApprove(USER_1, 100_000_000 ether, address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_1, 100_000_000 ether, address(protocol), type(uint256).max);
        protocol.initiateOpenPosition{ value: initiateOpenValidationCost + securityDepositValue }(
            minWstethAmount, params.initialPrice - (params.initialPrice * 2 / 10), "beef", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        // the adjusted lowest liquidation price divided by 2
        uint256 adjustedLowMockPythPrice = _getAdjustedPrice(params.initialLiqPrice / 2, assetDecimals, pythDecimals);
        mockPyth.setPrice(int64(int256(adjustedLowMockPythPrice)));
        mockPyth.setLastPublishTime(block.timestamp);

        uint256 adjustedLowMockChainlinkPrice =
            _getAdjustedPrice(params.initialLiqPrice / 2, assetDecimals, mockChainlinkOnChain.decimals());
        mockChainlinkOnChain.setLastPrice(int256(adjustedLowMockChainlinkPrice));
        mockChainlinkOnChain.setLastPublishTime(block.timestamp);

        // both price oracles should be equal
        (, int256 answerLow,,,) = mockChainlinkOnChain.latestRoundData();
        assertEq(int256(mockPyth.price()), answerLow);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatedTick(
            73_700, 0, 575_000_000_000_000_000_000, 1_587_048_886_761_876_745_500, -13_065_016_299_713_473_820
        );
        protocol.liquidate{ value: oracleMiddleware.validationCost("beef", ProtocolAction.Liquidation) }("beef", 1);

        // long expo should be negative
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");
        // vault expo should be equal zero
        assertEq(int256(protocol.getBalanceVault()), 0, "vault expo should be equal zero");

        uint128 adjustedPriceDown = _getAdjustedPrice(uint256(uint64(mockPyth.price())), pythDecimals, assetDecimals);
        uint128 minWstethAmountDown = uint128(minLongPosition * (10 ** assetDecimals) / adjustedPriceDown);

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo.selector);
        protocol.initiateOpenPosition{ value: initiateOpenValidationCost + securityDepositValue }(
            minWstethAmountDown, adjustedPriceDown / 2, "beef", EMPTY_PREVIOUS_DATA
        );

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.initiateDeposit{ value: initiateDepositValidationCost + securityDepositValue }(
            1 ether, "beef", EMPTY_PREVIOUS_DATA
        );

        vm.stopPrank();

        // disable all limits
        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0);

        vm.startPrank(USER_2);
        wstETH.mintAndApprove(USER_2, 200 ether, address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_2, 200 ether, address(protocol), type(uint256).max);

        protocol.initiateDeposit{ value: initiateDepositValidationCost + securityDepositValue }(
            1 ether, "beef", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        protocol.validateDeposit{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateDeposit) + securityDepositValue
        }("beef", EMPTY_PREVIOUS_DATA);

        vm.startPrank(USER_1);
        protocol.initiateOpenPosition{ value: initiateOpenValidationCost + securityDepositValue }(
            minWstethAmountDown * 10, adjustedPriceDown / 2, "beef", EMPTY_PREVIOUS_DATA
        );

        // long expo should be positive
        assertGt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be positive");
        // vault expo should be positive
        assertGt(int256(protocol.getBalanceVault()), 0, "vault expo should be positive");

        vm.stopPrank();
    }

    /**
     * @dev Get the price adjusted to the target decimals
     * @param price The price to adjust
     * @param originDecimals The origin decimals
     * @param targetDecimals The targeted decimals
     * @return adjustedPrice_ The adjusted price
     */
    function _getAdjustedPrice(uint256 price, uint256 originDecimals, uint256 targetDecimals)
        private
        pure
        returns (uint128 adjustedPrice_)
    {
        if (targetDecimals > originDecimals) {
            adjustedPrice_ = uint128(price * (10 ** (targetDecimals - originDecimals)));
        } else {
            adjustedPrice_ = uint128(price / (10 ** (originDecimals - targetDecimals)));
        }
    }
}
