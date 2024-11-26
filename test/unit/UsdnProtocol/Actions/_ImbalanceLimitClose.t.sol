// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN, DEPLOYER, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IBaseRebalancer } from "../../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature Test of the protocol expo limit for {_checkImbalanceLimitClose} function in a balanced state
 */
contract TestImbalanceLimitClose is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        // we enable only close limits and target imbalance
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, 600, 500, 501);
    }

    /**
     * @custom:scenario The {_checkImbalanceLimitClose} function should not revert when contract is balanced
     * and the wanted close position does not imbalance the protocol
     * @custom:given The protocol is in a balanced state
     * @custom:when The {_checkImbalanceLimitClose} function is called with a value below the close limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitClose() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues(false);
        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit / 2, longAmount);
    }

    /**
     * @custom:scenario The {_checkImbalanceLimitClose} function should not revert when the imbalance is equal to the
     * limit
     * @custom:given The protocol is in a balanced state
     * @custom:when The {_checkImbalanceLimitClose} function is called with values on the close limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitCloseOnLimit() public view {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues(false);
        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit - 1, longAmount);
    }

    /**
     * @custom:scenario The {_checkImbalanceLimitClose} function should revert when contract is balanced
     * and position value imbalance it
     * @custom:given The protocol is in a balanced state
     * @custom:when The {_checkImbalanceLimitClose} function is called with values above the close limit
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitCloseOutLimit() public {
        (int256 closeLimitBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues(false);
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, closeLimitBps)
        );
        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The {_checkImbalanceLimitClose} function should revert when action would imbalance the contract
     * @custom:given The protocol is in a balanced state
     * @custom:and A rebalancer is set
     * @custom:and The caller is the rebalancer
     * @custom:when The {_checkImbalanceLimitClose} function is called with values above the close limit
     * @custom:then The transaction should revert
     */
    function test_RevertWhen_checkImbalanceLimitCloseOutRebalancerLimit() public {
        vm.prank(ADMIN);
        protocol.setRebalancer(IBaseRebalancer(address(this)));

        (int256 closeLimitBps, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues(true);
        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, closeLimitBps)
        );

        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit, longAmount);
    }

    /**
     * @custom:scenario The {_checkImbalanceLimitClose} function should not revert when limit is disabled
     * @custom:given The protocol is in a balanced state
     * @custom:when The {_checkImbalanceLimitClose} function is called with values above the close limit
     * @custom:then The transaction should not revert
     */
    function test_checkImbalanceLimitCloseDisabled() public adminPrank {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues(false);

        // disable close limit
        protocol.setExpoImbalanceLimits(200, 200, 600, 0, 0, 0);

        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit + 1, longAmount);
    }

    /**
     * @custom:scenario The {_checkImbalanceLimitClose} function should revert when long expo equal 0
     * @custom:given The initial long positions is closed
     * @custom:and The protocol is imbalanced
     * @custom:when The {_checkImbalanceLimitClose} function is called
     * @custom:then The transaction should revert with {UsdnProtocolImbalanceLimitReached}
     */
    function test_RevertWhen_checkImbalanceLimitCloseZeroLongExpo() public {
        int256 initialCloseLimit = protocol.getCloseExpoImbalanceLimitBps();

        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);

        int24 tick = protocol.getHighestPopulatedTick();
        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(params.initialPrice);
        PreviousActionsData memory data = PreviousActionsData({ priceData: priceData, rawIndices: new uint128[](1) });

        vm.startPrank(DEPLOYER);
        protocol.initiateClosePosition(
            PositionId(tick, 0, 0),
            params.initialLong,
            DISABLE_MIN_PRICE,
            DEPLOYER,
            DEPLOYER,
            type(uint256).max,
            abi.encode(params.initialPrice),
            data,
            ""
        );
        _waitDelay();
        protocol.validateClosePosition(DEPLOYER, abi.encode(params.initialPrice), data);
        vm.stopPrank();

        assertEq(int256(protocol.getTotalExpo()) - int256(protocol.getBalanceLong()), 0, "long expo isn't 0");

        // reassign limits
        vm.prank(ADMIN);
        protocol.setExpoImbalanceLimits(0, 0, 0, uint256(initialCloseLimit), 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, type(int256).max)
        );
        protocol.i_checkImbalanceLimitClose(0, 0);
    }

    /**
     * @custom:scenario Check close imbalance when there are pending deposits
     * @custom:given The protocol is in an unbalanced state due to pending deposits
     * @custom:when The {_checkImbalanceLimitClose} function is called
     * @custom:then The transaction should revert with the expected imbalance
     */
    function test_RevertWhen_checkImbalanceLimitClosePendingVaultActions() public {
        (, uint256 longAmount, uint256 totalExpoValueToLimit) = _getCloseLimitValues(false);

        // this action will affect the vault trading expo once it's validated
        setUpUserPositionInVault(USER_1, ProtocolAction.InitiateDeposit, params.initialDeposit, params.initialPrice);

        int256 currentVaultExpo = int256(protocol.getBalanceVault()) + protocol.getPendingBalanceVault();
        int256 newLongExpo =
            int256(protocol.getTotalExpo() - totalExpoValueToLimit) - int256(protocol.getBalanceLong() - longAmount);
        int256 expectedImbalance = (currentVaultExpo - newLongExpo) * int256(Constants.BPS_DIVISOR) / newLongExpo;

        vm.expectRevert(
            abi.encodeWithSelector(
                IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector, uint256(expectedImbalance)
            )
        );
        protocol.i_checkImbalanceLimitClose(totalExpoValueToLimit, longAmount);
    }

    /**
     * @notice Get close limit values at with the protocol revert
     * @param isRebalancer Flag to check if the caller is a rebalancer
     * @return closeLimitBps_ The close limit bps
     * @return longAmount_ The long amount
     * @return totalExpoValueToLimit_ The total expo value to imbalance the protocol
     */
    function _getCloseLimitValues(bool isRebalancer)
        private
        view
        returns (int256 closeLimitBps_, uint256 longAmount_, uint256 totalExpoValueToLimit_)
    {
        uint256 longExpo = protocol.getTotalExpo() - protocol.getBalanceLong();

        closeLimitBps_ = isRebalancer
            ? protocol.getRebalancerCloseExpoImbalanceLimitBps() + 1
            : protocol.getCloseExpoImbalanceLimitBps() + 1;

        uint256 vaultExpo = protocol.getBalanceVault() + uint256(protocol.getPendingBalanceVault());

        uint256 longExpoLimit = vaultExpo * Constants.BPS_DIVISOR / (uint256(closeLimitBps_) + Constants.BPS_DIVISOR);

        // the long expo value to reach limit from current long expo
        uint256 longExpoValueToLimit = longExpo - longExpoLimit;

        // long amount to reach limit from longExpoValueToLimit and any leverage
        longAmount_ =
            longExpoValueToLimit * 10 ** Constants.LEVERAGE_DECIMALS / protocol.i_getLeverage(2000 ether, 1500 ether);

        // total expo value to reach limit
        totalExpoValueToLimit_ = longExpoValueToLimit + longAmount_;
    }
}
