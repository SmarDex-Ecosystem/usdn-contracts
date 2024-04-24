// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import {
    PendingAction, ProtocolAction, WithdrawalPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The withdraw function of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolActionsValidateWithdrawal is UsdnProtocolBaseFixture {
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
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price increases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $3000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.425409641068422497
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.425409641068422497
     */
    function test_validateWithdrawPriceUp() public {
        skip(3600);
        _checkValidateWithdrawWithPrice(uint128(2500 ether), uint128(3000 ether), 0.425409641068422497 ether);
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price decreases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $2000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.455218606057907765
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.455218606057907765
     */
    function test_validateWithdrawPriceDown() public {
        skip(3600);
        _checkValidateWithdrawWithPrice(uint128(2500 ether), uint128(2000 ether), 0.455218606057907765 ether);
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
        protocol.initiateWithdrawal{ value: validationCost }(USDN_AMOUNT, currentPrice, EMPTY_PREVIOUS_DATA);

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateWithdrawal);
        uint256 balanceBefore = address(this).balance;
        protocol.validateWithdrawal{ value: 0.5 ether }(currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @dev Create a withdrawal at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted
     * event and the resulting state.
     * @param initialPrice price of the asset at the time of withdrawal initiation
     * @param assetPrice price of the asset at the time of withdrawal validation
     * @param expectedAssetAmount expected amount of asset withdrawn
     */
    function _checkValidateWithdrawWithPrice(uint128 initialPrice, uint128 assetPrice, uint256 expectedAssetAmount)
        public
    {
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        bytes memory currentPrice = abi.encode(initialPrice);
        protocol.initiateWithdrawal(withdrawShares, currentPrice, EMPTY_PREVIOUS_DATA);

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
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
        emit ValidatedWithdrawal(address(this), withdrawnAmount, USDN_AMOUNT, withdrawal.timestamp); // expected event
        protocol.validateWithdrawal(currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "final usdn balance");
        assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance + withdrawnAmount, "final wstETH balance");
    }

    /**
     * @custom:scenario The user validates a withdrawal action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls validateWithdrawal with too much ether
     * @custom:and A receive() function that calls validateWithdrawal again
     * @custom:when The user calls validateWithdrawal again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_validateWithdrawalCalledWithReentrancy() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.validateWithdrawal(currentPrice, EMPTY_PREVIOUS_DATA);
            return;
        }

        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, DEPOSIT_AMOUNT, 2000 ether);

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.validateWithdrawal.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.validateWithdrawal{ value: 1 }(currentPrice, EMPTY_PREVIOUS_DATA);
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_validateWithdrawalCalledWithReentrancy();
            _reenter = false;
        }
    }
}
