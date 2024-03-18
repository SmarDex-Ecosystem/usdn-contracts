// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_imbalanceLimitWithdrawal` function in balanced state
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
     * @custom:scenario The `_imbalanceLimitWithdrawal` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitWithdrawal` function is called with a value below the withdrawal limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawal() public view {
        (, uint256 longExpoValueToLimit) = _setupWithdrawal();
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit);
    }

    /**
     * @custom:scenario The `_imbalanceLimitWithdrawal` function should revert when vault expo equal 0
     * @custom:given The protocol is balanced
     * @custom:and A long position is opened
     * @custom:and Price crash below any liquidation prices
     * @custom:and The first position is liquidated
     * @custom:and The last liquidation isn't involved during a day which leads bad debt
     * @custom:when The `_imbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalZeroVaultExpo() public {
        // mint and approve wsteth
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(params.initialPrice);

        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: new uint128[](1) });
        // initiate open
        protocol.initiateOpenPosition(0.1 ether, params.initialPrice / 2, abi.encode(params.initialPrice), data);

        // wait more than 2 blocks
        _waitDelay();

        // validate open position
        protocol.validateOpenPosition(abi.encode(params.initialPrice), data);

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
     * @custom:scenario The `_imbalanceLimitWithdrawal` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitWithdrawal` function is called
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitWithdrawalDisabled() public {
        (, uint256 longExpoValueToLimit) = _setupWithdrawal();

        // disable withdrawal limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimitsBps(200, 200, 0, 600);

        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit + 1);
    }

    /**
     * @custom:scenario The `_imbalanceLimitWithdrawal` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitWithdrawal` function is called with a value above the withdrawal limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitWithdrawalOutLimit() public {
        (uint256 imbalanceBps, uint256 longExpoValueToLimit) = _setupWithdrawal();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
        );
        protocol.i_imbalanceLimitWithdrawal(longExpoValueToLimit + 1);
    }

    function _setupWithdrawal() private view returns (uint256 imbalanceBps_, uint256 longExpoValueToLimit_) {
        uint256 vaultExpo_ = protocol.getBalanceVault();
        // initial withdrawal limit bps
        (,, int256 withdrawalLimit,) = protocol.getExpoImbalanceLimitsBps();
        // imbalance bps
        imbalanceBps_ = uint256(withdrawalLimit);
        // current long expo value to imbalance the protocol
        longExpoValueToLimit_ = vaultExpo_ * imbalanceBps_ / protocol.BPS_DIVISOR();
    }
}
