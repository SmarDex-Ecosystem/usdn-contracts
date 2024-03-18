// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { PreviousActionsData } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_imbalanceLimitOpen` function in balanced state
 */
contract TestExpoLimitsOpen is UsdnProtocolBaseFixture {
    function setUp() public {
        SetUpParams memory params = DEFAULT_PARAMS;
        params.enableLimits = true;
        params.initialDeposit = 49.199702697034631562 ether;
        params.initialLong = 50 ether;
        super._setUp(params);
    }

    /**
     * @custom:scenario The `_imbalanceLimitOpen` function should not revert when contract is balanced
     * and position is within limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitOpen` function is called with a value below the open limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitOpen() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _setupOpen();
        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `_imbalanceLimitOpen` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitOpen` function is called with values above the open limit
     * @custom:then The transaction should not revert
     */
    function test_imbalanceLimitOpenDisabled() public {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _setupOpen();

        // disable open limit
        vm.prank(ADMIN);
        protocol.setOpenExpoImbalanceLimitBps(0);

        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `_imbalanceLimitOpen` function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_imbalanceLimitOpen` function is called with values above the open limit
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitOpenOutLimit() public {
        (uint256 imbalanceBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _setupOpen();
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, imbalanceBps)
        );
        protocol.i_imbalanceLimitOpen(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The `_imbalanceLimitOpen` function should revert when vault expo equal 0
     * @custom:given The protocol is balanced
     * @custom:and A long position is opened
     * @custom:and Price crash below any liquidation prices
     * @custom:and The first position is liquidated
     * @custom:and The last liquidation isn't involved during a day which leads bad debt
     * @custom:when The `_imbalanceLimitOpen` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWith_imbalanceLimitOpenZeroVaultExpo() public {
        // mint and approve wsteth
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);

        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(params.initialPrice);

        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: new uint128[](1) });

        // initiate open
        protocol.initiateOpenPosition(0.1 ether, params.initialPrice / 2, abi.encode(params.initialPrice), data);

        // wait more than 2 blocks
        skip(25);

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
        protocol.i_imbalanceLimitOpen(0, 0);
    }

    function _setupOpen()
        private
        view
        returns (uint256 imbalanceBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current vault expo
        uint256 vaultExpo = protocol.getBalanceVault();
        // imbalance bps
        imbalanceBps_ = uint256(protocol.getOpenExpoImbalanceLimitBps());
        // current long expo value to unbalance protocol
        uint256 longExpoValueToLimit = vaultExpo * imbalanceBps_ / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and leverage
        longAmount_ =
            longExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = longExpoValueToLimit + longAmount_;
    }
}
