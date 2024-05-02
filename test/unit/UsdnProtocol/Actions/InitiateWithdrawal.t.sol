// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    PendingAction, ProtocolAction, WithdrawalPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The withdraw function of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolActionsInitiateWithdrawal is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint128 internal constant USDN_AMOUNT = 1000 ether;
    uint152 internal withdrawShares;
    uint256 internal initialWstETHBalance;
    uint256 internal initialUsdnBalance;
    uint256 internal initialUsdnShares;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        withdrawShares = USDN_AMOUNT * uint152(usdn.MAX_DIVISOR());
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at price $2000
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, 2000 ether);
        initialUsdnBalance = usdn.balanceOf(address(this));
        initialUsdnShares = usdn.sharesOf(address(this));
        initialWstETHBalance = wstETH.balanceOf(address(this));
    }

    /**
     * @custom:scenario Test the setup function output
     * @custom:given The user deposited 1 wstETH at price $2000
     * @custom:then The user's USDN balance is 2000 USDN
     * @custom:and The user's wstETH balance is 9 wstETH
     */
    function test_withdrawSetUp() public {
        // Using the price computed with the default position fees
        assertEq(initialUsdnBalance, 2000 * DEPOSIT_AMOUNT, "initial usdn balance");
        assertEq(initialUsdnShares, 2000 * DEPOSIT_AMOUNT * usdn.MAX_DIVISOR(), "initial usdn shares");
        assertEq(initialWstETHBalance, 0, "initial wstETH balance");
    }

    /**
     * @custom:scenario The user initiates a withdrawal for 1000 USDN
     * @custom:given The price of the asset is $3000
     * @custom:when The user initiates a withdrawal for 1000e36 shares of USDN
     * @custom:then The user's USDN shares balance decreases by 1000e36
     * @custom:and The protocol's USDN shares balance increases by 1000e36
     * @custom:and The protocol emits an `InitiatedWithdrawal` event
     * @custom:and The USDN total supply does not change yet
     * @custom:and The protocol's wstETH balance does not change yet
     * @custom:and The user has a pending action of type `InitiateWithdrawal` with the amount of 1000 USDN
     * @custom:and The pending action is not actionable yet
     * @custom:and The pending action is actionable after the validation deadline has elapsed
     */
    function test_initiateWithdraw() public {
        _initiateWithdraw(address(this));
    }

    /**
     * @custom:scenario The user initiates a withdrawal for 1000 USDN with another address as the beneficiary
     * @custom:given The price of the asset is $3000
     * @custom:when The user initiates a withdraw for 1000 USDN with another address as the beneficiary
     * @custom:then The protocol emits an `InitiatedWithdrawal` event with the right beneficiary
     * @custom:and The user has a pending action of type `InitiateWithdrawal` with the right beneficiary
     */
    function test_initiateWithdrawForAnotherAddress() public {
        _initiateWithdraw(USER_1);
    }

    function _initiateWithdraw(address to) internal {
        bytes memory currentPrice = abi.encode(uint128(3000 ether));
        uint256 protocolUsdnInitialShares = usdn.sharesOf(address(protocol));

        vm.expectEmit();
        emit InitiatedWithdrawal(address(this), to, USDN_AMOUNT, block.timestamp); // expected event
        protocol.initiateWithdrawal(withdrawShares, currentPrice, EMPTY_PREVIOUS_DATA, to);

        assertEq(usdn.sharesOf(address(this)), initialUsdnShares - withdrawShares, "usdn user balance");
        assertEq(usdn.sharesOf(address(protocol)), protocolUsdnInitialShares + withdrawShares, "usdn protocol balance");
        // no wstETH should be given to the user yet
        assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance, "wstETH user balance");
        // no USDN should be burned yet
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + initialUsdnBalance, "usdn total supply");
        // the pending action should not yet be actionable by a third party
        (PendingAction[] memory actions, uint128[] memory rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "no pending action");

        WithdrawalPendingAction memory action =
            protocol.i_toWithdrawalPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.common.action == ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.common.timestamp, block.timestamp, "action timestamp");
        assertEq(action.common.user, address(this), "action user");
        assertEq(action.common.to, to, "action to");
        uint256 shares = protocol.i_mergeWithdrawalAmountParts(action.sharesLSB, action.sharesMSB);
        assertEq(shares, withdrawShares, "action shares");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions[0].common.user, address(this), "pending action user");
        assertEq(actions[0].common.to, to, "pending action user");
        assertEq(rawIndices[0], 1, "raw index");
    }

    /**
     * @custom:scenario The user initiates a withdrawal for 0 USDN
     * @custom:when The user initiates a withdrawal for 0 USDN
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateWithdrawal(0, currentPrice, EMPTY_PREVIOUS_DATA, address(this));
    }

    /**
     * @custom:scenario The user initiates a deposit with parameter to defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiate a withdrawal with parameter to address defined at 0
     * @custom:then The protocol reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.initiateWithdrawal(1 ether, currentPrice, EMPTY_PREVIOUS_DATA, address(0));
    }

    /**
     * @custom:scenario The user sends too much ether when initiating a withdrawal
     * @custom:given The user withdraws 1 wstETH
     * @custom:when The user sends 0.5 ether as value in the `initiateWithdrawal` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_initiateWithdrawEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        uint256 balanceBefore = address(this).balance;
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateWithdrawal);
        protocol.initiateWithdrawal{ value: validationCost }(
            USDN_AMOUNT, currentPrice, EMPTY_PREVIOUS_DATA, address(this)
        );
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user initiates a withdrawal action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls initiateWithdrawal with too much ether
     * @custom:and A receive() function that calls initiateWithdrawal again
     * @custom:when The user calls initiateWithdrawal again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_initiateWithdrawalCalledWithReentrancy() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateWithdrawal(USDN_AMOUNT, currentPrice, EMPTY_PREVIOUS_DATA, address(this));
            return;
        }

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, 2000 ether);

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateWithdrawal.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateWithdrawal{ value: 1 }(USDN_AMOUNT, currentPrice, EMPTY_PREVIOUS_DATA, address(this));
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_initiateWithdrawalCalledWithReentrancy();
            _reenter = false;
        }
    }
}
