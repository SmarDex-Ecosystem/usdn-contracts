// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import {
    PendingAction, ProtocolAction, WithdrawalPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @custom:feature The withdraw function of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolWithdraw is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint128 internal constant USDN_AMOUNT = 1000 ether;
    uint152 internal withdrawShares;
    uint256 internal initialWstETHBalance;
    uint256 internal initialUsdnBalance;
    uint256 internal initialUsdnShares;

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

        WithdrawalPendingAction memory action = protocol.i_toWithdrawalPendingAction(protocol.getUserPendingAction(to));
        assertTrue(action.action == ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.to, to, "action to");
        uint256 shares = protocol.i_mergeWithdrawalAmountParts(action.sharesLSB, action.sharesMSB);
        assertEq(shares, withdrawShares, "action shares");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (actions, rawIndices) = protocol.getActionablePendingActions(address(0));
        assertEq(actions[0].user, address(this), "pending action user");
        assertEq(action.to, to, "pending action user");
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
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price increases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $3000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.347635290659860583
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.347635290659860583
     */
    function test_validateWithdrawPriceUp() public {
        _checkValidateWithdrawWithPrice(
            uint128(2500 ether), uint128(3000 ether), 0.347635290659860583 ether, address(this)
        );
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price decreases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $2000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.416891976723560318
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.416891976723560318
     */
    function test_validateWithdrawPriceDown() public {
        _checkValidateWithdrawWithPrice(
            uint128(2500 ether), uint128(2000 ether), 0.416891976723560318 ether, address(this)
        );
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
     * @custom:scenario The user sends too much ether when validating a withdrawal
     * @custom:given The user initiated a withdrawal of 1000 USDN and validates it
     * @custom:when The user sends 0.5 ether as value in the `validateWithdrawal` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_validateWithdrawEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        // initiate
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateWithdrawal);
        protocol.initiateWithdrawal{ value: validationCost }(
            USDN_AMOUNT, currentPrice, EMPTY_PREVIOUS_DATA, address(this)
        );

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateWithdrawal);
        uint256 balanceBefore = address(this).balance;
        protocol.validateWithdrawal{ value: 0.5 ether }(address(this), currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN with another address as the beneficiary
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2000 at the moment of initiation and validation
     * @custom:when The user validates the withdrawal with another address as the beneficiary
     * @custom:then The protocol emits a `ValidatedWithdrawal` event with the right beneficiary
     */
    function test_validateWithdrawDifferentToAddress() public {
        _checkValidateWithdrawWithPrice(uint128(2000 ether), uint128(2000 ether), 0.5 ether, USER_1);
    }

    /**
     * @dev Create a withdrawal at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted
     * event and the resulting state.
     * @param initialPrice price of the asset at the time of withdrawal initiation
     * @param assetPrice price of the asset at the time of withdrawal validation
     * @param expectedAssetAmount expected amount of asset withdrawn
     */
    function _checkValidateWithdrawWithPrice(
        uint128 initialPrice,
        uint128 assetPrice,
        uint256 expectedAssetAmount,
        address to
    ) public {
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        bytes memory currentPrice = abi.encode(initialPrice);
        protocol.initiateWithdrawal(withdrawShares, currentPrice, EMPTY_PREVIOUS_DATA, to);

        PendingAction memory pending = protocol.getUserPendingAction(to);
        WithdrawalPendingAction memory withdrawal = protocol.i_toWithdrawalPendingAction(pending);

        uint256 vaultBalance = protocol.getBalanceVault(); // save for withdrawn amount calculation in case price
            // decreases

        // wait the required delay between initiation and validation
        _waitDelay();

        currentPrice = abi.encode(assetPrice);

        // if price increases, we need to use the new balance to calculate the withdrawn amount
        if (assetPrice > initialPrice) {
            vaultBalance = uint256(protocol.i_vaultAssetAvailable(assetPrice));
        }

        PriceInfo memory withdrawalPrice =
            protocol.i_getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, abi.encode(assetPrice));

        // Apply fees on price
        uint256 withdrawalPriceWithFees =
            withdrawalPrice.price - (withdrawalPrice.price * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.
        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = uint256(
            protocol.i_vaultAssetAvailable(
                withdrawal.totalExpo,
                withdrawal.balanceVault,
                withdrawal.balanceLong,
                withdrawalPriceWithFees.toUint128(), // new price
                withdrawal.assetPrice // old price
            )
        );
        uint256 available;
        if (available1 <= available2) {
            available = available1;
        } else {
            available = available2;
        }

        uint256 shares = protocol.i_mergeWithdrawalAmountParts(withdrawal.sharesLSB, withdrawal.sharesMSB);
        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 withdrawnAmount = FixedPointMathLib.fullMulDiv(shares, available, withdrawal.usdnTotalShares);
        assertEq(withdrawnAmount, expectedAssetAmount, "asset amount");

        vm.expectEmit();
        emit ValidatedWithdrawal(address(this), to, withdrawnAmount, USDN_AMOUNT, withdrawal.timestamp); // expected
            // event
        protocol.validateWithdrawal(to, currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "final usdn balance");
        if (to == address(this)) {
            assertEq(wstETH.balanceOf(to), initialWstETHBalance + withdrawnAmount, "final wstETH balance");
        } else {
            assertEq(wstETH.balanceOf(to), withdrawnAmount, "final wstETH balance");
            assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance, "final wstETH balance");
        }
    }

    // test refunds
    receive() external payable { }
}
