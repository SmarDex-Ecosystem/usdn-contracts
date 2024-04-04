// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER, USER_1 } from "test/utils/Constants.sol";

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

        uint256 assetDecimals = uint256(uint8(protocol.getAssetDecimals()));
        uint256 pythDecimals = uint256(-int256(mockPyth.expo()));

        uint128 initialPrice = _getAdjustedPrice(uint256(uint64(mockPyth.price())), assetDecimals, pythDecimals);

        uint256 minLongValue = uint256(protocol.getMinLongPosition());
        uint128 minLongAmount = uint128(minLongValue * (10 ** assetDecimals) / initialPrice);
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 initiateValidationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition);

        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmount, params.initialLiqPrice + (params.initialLiqPrice * 2 / 10), "", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        uint256 adjustedLowMockPrice = _getAdjustedPrice(params.initialLiqPrice / 2, pythDecimals, assetDecimals);

        mockPyth.setPrice(int64(int256(adjustedLowMockPrice)));

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }("beef", EMPTY_PREVIOUS_DATA);

        // long expo should be negative
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");

        uint128 priceDown = _getAdjustedPrice(uint256(uint64(mockPyth.price())), assetDecimals, pythDecimals);

        uint128 minLongAmountDown = uint128(minLongValue * (10 ** assetDecimals) / priceDown);

        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmountDown, priceDown / 2, "", EMPTY_PREVIOUS_DATA
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
        vm.startPrank(USER_1);
        (bool success,) = address(wstETH).call{ value: 200 ether }("");
        require(success, "Recover negative long expo: wstETH mint failed");
        wstETH.approve(address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_1, 200 ether, address(protocol), type(uint256).max);

        uint256 assetDecimals = uint256(uint8(protocol.getAssetDecimals()));
        uint256 pythDecimals = uint256(-int256(mockPyth.expo()));

        uint128 initialPrice = _getAdjustedPrice(uint256(uint64(mockPyth.price())), assetDecimals, pythDecimals);

        uint256 minLongValue = uint256(protocol.getMinLongPosition());
        uint128 minLongAmount = uint128(minLongValue * (10 ** assetDecimals) / initialPrice);
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 initiateValidationCost = oracleMiddleware.validationCost("", ProtocolAction.InitiateOpenPosition);

        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmount, params.initialPrice - (params.initialPrice * 2 / 10), "", EMPTY_PREVIOUS_DATA
        );

        vm.stopPrank();

        uint256 adjustedLowMockPrice = _getAdjustedPrice(params.initialLiqPrice / 2, pythDecimals, assetDecimals);
        mockPyth.setPrice(int64(int256(adjustedLowMockPrice)));

        skip(20);
        mockPyth.setLastPublishTime(block.timestamp);
        protocol.liquidate{ value: oracleMiddleware.validationCost("beef", ProtocolAction.Liquidation) }("beef", 1);

        // long expo should be negative
        assertLt(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo should be negative");
        // vault expo should be zero
        assertEq(int256(protocol.getBalanceVault()), 0, "vault expo should be negative");

        uint128 priceDown = _getAdjustedPrice(uint256(uint64(mockPyth.price())), assetDecimals, pythDecimals);
        uint128 minLongAmountDown = uint128(minLongValue * (10 ** assetDecimals) / priceDown);

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo.selector);
        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmountDown, priceDown / 2, "beef", EMPTY_PREVIOUS_DATA
        );

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector);
        protocol.initiateDeposit{ value: initiateValidationCost + securityDepositValue }(
            1 ether, "beef", EMPTY_PREVIOUS_DATA
        );

        vm.prank(DEPLOYER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0);

        vm.startPrank(USER_1);
        protocol.initiateOpenPosition{ value: initiateValidationCost + securityDepositValue }(
            minLongAmountDown * 10, priceDown / 2, "beef", EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.ValidateOpenPosition)
        }("beef", EMPTY_PREVIOUS_DATA);

        // TODO verify deposit
        protocol.initiateDeposit{
            value: oracleMiddleware.validationCost("beef", ProtocolAction.InitiateDeposit) + securityDepositValue
        }(1 ether, "beef", EMPTY_PREVIOUS_DATA);

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
        if (originDecimals > targetDecimals) {
            adjustedPrice_ = uint128(price * (10 ** (originDecimals - targetDecimals)));
        } else {
            adjustedPrice_ = uint128(price / (10 ** (targetDecimals - originDecimals)));
        }
    }
}
