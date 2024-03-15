// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `imbalanceLimitWithdrawal` function in balanced state
 */
contract TestExpoLimitsWithdrawal is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitWithdrawal` function is called with a value inside limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawal() public view {
        (, uint256 longExpoValueToLimit) = _getWithdrawalValues();
        // call `imbalanceLimitWithdrawal` function with longExpoValueToLimit
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` function should revert when vault expo equal 0
     * @custom:given The protocol is balanced
     * @custom:and A long position is opened
     * @custom:and Price crash below any liquidation prices
     * @custom:and The first position is liquidated
     * @custom:and The last liquidation isn't involved during a day which leads bad debt
     * @custom:when The `imbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalZeroVaultExpo() public {
        // mint and approve wsteth
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        // initiate open
        protocol.initiateOpenPosition(
            0.1 ether, params.initialPrice / 2, abi.encode(params.initialPrice), bytes("bird")
        );

        // wait more than 2 blocks
        skip(25);

        // validate open position
        protocol.validateOpenPosition(abi.encode(params.initialPrice), abi.encode(params.initialPrice));

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
        protocol.i_imbalanceLimitWithdrawal(0);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` function should not revert
     * when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawalDisabled() public {
        (, uint256 longExpoValueToLimit) = _getWithdrawalValues();

        // disable withdrawal limit
        vm.prank(ADMIN);
        protocol.setWithdrawalExpoImbalanceLimit(0);

        // should not revert
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `imbalanceLimitWithdrawal` function is called with a value above the withdrawal limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalOutLimit() public {
        (uint256 imbalanceBps, uint256 longExpoValueToLimit) = _getWithdrawalValues();
        // call `imbalanceLimitWithdrawal` function with vaultExpoValueToLimit + 1
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
        );
        // should revert
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit + 1);
    }

    function _getWithdrawalValues() private view returns (uint256 imbalanceBps_, uint256 longExpoValueToLimit_) {
        uint256 vaultExpo_ = protocol.getBalanceVault();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getWithdrawalExpoImbalanceLimit());
        // current long expo value to imbalance the protocol
        longExpoValueToLimit_ = vaultExpo_ * imbalanceBps_ / protocol.BPS_DIVISOR();
    }
}
