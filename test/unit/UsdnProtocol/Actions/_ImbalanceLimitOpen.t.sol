// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitOpen` function in balanced state
 */
contract TestExpoLimitsOpen is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.flags.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitOpen` function is called with a value below the open limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitOpen() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();
        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitOpen` function is called with values above the open limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitOpenDisabled() public {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();

        // disable open limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 200, 600, 600);

        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitOpen` function is called with values above the open limit
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitOpenOutLimit() public {
        (int256 openLimitBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, openLimitBps)
        );
        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should revert when vault expo equal 0
     * @custom:given The protocol is balanced
     * @custom:and A long position is opened
     * @custom:and Price crash below any liquidation prices
     * @custom:and The first position is liquidated
     * @custom:and The last liquidation isn't involved during a day which leads bad debt
     * @custom:when The `_checkImbalanceLimitOpen` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitOpenZeroVaultExpo() public {
        setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 0.1 ether, params.initialPrice / 2, params.initialPrice
        );

        // new price below any position but only one will be liquidated
        protocol.liquidate(abi.encode(params.initialPrice / 3), 1);

        // wait a day without liquidation
        skip(1 days);

        // liquidate the last position but leads bad debt
        protocol.liquidate(abi.encode(params.initialPrice / 3), 1);

        // vault expo should be zero
        assertEq(protocol.getBalanceVault(), 0, "vault expo isn't 0");

        // should revert
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidVaultExpo.selector);
        protocol.i_checkImbalanceLimitOpen(0, 0);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should pass when long expo
     * is negative and by adding open position remain negative
     * @custom:given The initial long position
     * @custom:and The asset price is below the liquidation price
     * @custom:and The initial position is not liquidated
     * @custom:and The current long expo is negative
     * @custom:when The `_checkImbalanceLimitOpen` function is called
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitOpenNegativeLongExpo() public {
        setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 0.1 ether, params.initialPrice / 2, params.initialPrice
        );

        // new price below any position but only one will be liquidated
        protocol.liquidate(abi.encode(params.initialPrice / 3), 1);

        int256 currentLongExpo = int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong());
        assertLt(currentLongExpo, 0);

        protocol.i_checkImbalanceLimitOpen(0, 0);
    }

    function _getOpenLimitValues()
        private
        view
        returns (int256 openLimitBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current vault expo
        uint256 vaultExpo = protocol.getBalanceVault();
        // open limit bps
        (openLimitBps_,,,) = protocol.getExpoImbalanceLimits();
        // current long expo value to unbalance protocol
        uint256 longExpoValueToLimit = vaultExpo * uint256(openLimitBps_) / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and any leverage
        longAmount_ =
            longExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = longExpoValueToLimit + longAmount_;
    }
}
