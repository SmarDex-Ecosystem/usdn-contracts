// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, DEPLOYER } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature Test of the protocol expo limit for `_checkImbalanceLimitOpen` function in balanced state
 */
contract TestExpoLimitsOpen is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        // we enable only open limit
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(200, 0, 0, 0, 0, 0);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should not revert when contract is balanced
     * and the wanted open position does not imbalance the protocol
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitOpen` function is called with a value below the open limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitOpen() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();
        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit / 2, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should not revert when the imballance is equal to the
     * limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitOpen` function is called with values on the open limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitOpenOnLimit() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();
        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit - 1, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The `_checkImbalanceLimitOpen` function is called with values above the open limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitOpenDisabled() public adminPrank {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();

        // disable open limit
        protocol.setExpoImbalanceLimits(0, 200, 600, 600, 500, 300);

        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit, longAmount);
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
        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The `_checkImbalanceLimitOpen` function should revert when vault expo equal 0
     * @custom:given The vault has zero balance / expo
     * @custom:when The `_checkImbalanceLimitOpen` function is called
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitOpenZeroVaultExpo() public {
        protocol.emptyVault();

        // should revert
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, type(int256).max)
        );
        protocol.i_checkImbalanceLimitOpen(0, 0);
    }

    /**
     * @custom:scenario Check open imbalance when there are pending withdrawals
     * @custom:given The protocol is in an unbalanced state due to pending withdrawals
     * @custom:when The `_checkImbalanceLimitOpen` function is called
     * @custom:then The transaction should revert with the expected imbalance
     */
    function test_RevertWhen_checkImbalanceLimitOpenPendingVaultActions() public {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getOpenLimitValues();

        // this action will affect the vault trading expo once it's validated
        vm.startPrank(DEPLOYER);
        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint152(usdn.sharesOf(DEPLOYER) / 2),
            DISABLE_AMOUNT_OUT_MIN,
            DEPLOYER,
            DEPLOYER,
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        int256 currentVaultExpo = int256(protocol.getBalanceVault()) + protocol.getPendingBalanceVault();
        int256 expectedImbalance = (
            int256(protocol.getTotalExpo() + totalExpoValueToLimit) - int256(protocol.getBalanceLong() + longAmount)
                - currentVaultExpo
        ) * int256(protocol.BPS_DIVISOR()) / currentVaultExpo;
        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, uint256(expectedImbalance)
            )
        );
        protocol.i_checkImbalanceLimitOpen(totalExpoValueToLimit, longAmount);
    }

    /**
     * @notice Get the open limit values at with the protocol revert
     * @return openLimitBps_ The open limit bps
     * @return longAmount_ The long amount
     * @return totalExpoValueToLimit_ The total expo value to imbalance the protocol
     */
    function _getOpenLimitValues()
        private
        view
        returns (int256 openLimitBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        // current vault expo
        int256 vaultExpo = int256(protocol.getBalanceVault()) + protocol.getPendingBalanceVault();
        // open limit bps
        openLimitBps_ = protocol.getOpenExpoImbalanceLimitBps() + 1;
        // current long expo value to unbalance protocol
        uint256 longExpoValueToLimit = uint256(vaultExpo) * uint256(openLimitBps_) / protocol.BPS_DIVISOR();
        // long amount for vaultExpoValueToLimit and any leverage
        longAmount_ =
            longExpoValueToLimit * 10 ** protocol.LEVERAGE_DECIMALS() / protocol.i_getLeverage(2000 ether, 1500 ether);
        // current total expo value to imbalance the protocol
        totalExpoValueToLimit_ = longExpoValueToLimit + longAmount_ + 1;
    }
}
