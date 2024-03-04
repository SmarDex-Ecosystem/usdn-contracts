// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import { PendingAction, ProtocolAction, VaultPendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";

/**
 * @custom:feature The withdraw function of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolWithdraw is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint128 internal constant USDN_AMOUNT = 1000 ether;
    uint256 internal initialWstETHBalance;
    uint256 internal initialUsdnBalance;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), INITIAL_WSTETH_BALANCE);
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at price $2000
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        protocol.initiateDeposit(DEPOSIT_AMOUNT, currentPrice, "");
        protocol.validateDeposit(currentPrice, "");
        initialUsdnBalance = usdn.balanceOf(address(this));
        initialWstETHBalance = wstETH.balanceOf(address(this));
    }

    /**
     * @custom:scenario Test the setup function output
     * @custom:given The user deposited 1 wstETH at price $2000
     * @custom:then The user's USDN balance is 1999.2 USDN
     * @custom:and The user's wstETH balance is 9 wstETH
     */
    function test_withdrawSetUp() public {
        // Using the price computed with the default position fees
        assertEq(initialUsdnBalance, 1_998_806_479_853_710_648_779 * (DEPOSIT_AMOUNT / 1e18), "initial usdn balance");
        assertEq(initialWstETHBalance, INITIAL_WSTETH_BALANCE - DEPOSIT_AMOUNT, "initial wstETH balance");
    }

    /**
     * @custom:scenario The user initiates a withdrawal for 1000 USDN
     * @custom:given The price of the asset is $3000
     * @custom:when The user initiates a withdraw for 1000 USDN
     * @custom:then The user's USDN balance decreases by 1000 USDN
     * @custom:and The protocol's USDN balance increases by 1000 USDN
     * @custom:and The protocol emits an `InitiatedWithdrawal` event
     * @custom:and The USDN total supply does not change yet
     * @custom:and The protocol's wstETH balance does not change yet
     * @custom:and The user has a pending action of type `InitiateWithdrawal` with the amount of 1000 USDN
     * @custom:and The pending action is not actionable yet
     * @custom:and The pending action is actionable after the validation deadline has elapsed
     */
    function test_initiateWithdraw() public {
        skip(3600);
        bytes memory currentPrice = abi.encode(uint128(3000 ether));

        vm.expectEmit();
        emit InitiatedWithdrawal(address(this), USDN_AMOUNT); // expected event
        protocol.initiateWithdrawal(USDN_AMOUNT, currentPrice, "");

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "usdn user balance");
        assertEq(usdn.balanceOf(address(protocol)), USDN_AMOUNT, "usdn protocol balance");
        // no wstETH should be given to the user yet
        assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance, "wstETH user balance");
        // no USDN should be burned yet
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + initialUsdnBalance, "usdn total supply");
        // the pending action should not yet be actionable by a third party
        vm.prank(address(0)); // simulate front-end call by someone else
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.amount, USDN_AMOUNT, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.validationDeadline() + 1);
        vm.prank(address(0)); // simulate front-end call by someone else
        action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(this), "pending action user");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 0 USDN
     * @custom:when The user validates a withdrawal for 0 USDN
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateWithdrawal(0, currentPrice, "");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price increases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $3000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.425585189969251644
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.425585189969251644
     */
    function test_validateWithdrawPriceUp() public {
        skip(3600);
        _checkValidateWithdrawWithPrice(uint128(2500 ether), uint128(3000 ether), 0.425585189969251644 ether);
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price decreases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2500 at the moment of initiation
     * @custom:and The price of the asset is $2000 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0.455406157755485910
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.455406157755485910
     */
    function test_validateWithdrawPriceDown() public {
        skip(3600);
        _checkValidateWithdrawWithPrice(uint128(2500 ether), uint128(2000 ether), 0.45540615775548591 ether);
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
        protocol.initiateWithdrawal{ value: validationCost }(USDN_AMOUNT, currentPrice, "");
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
        protocol.initiateWithdrawal{ value: validationCost }(USDN_AMOUNT, currentPrice, "");

        skip(oracleMiddleware.validationDelay() + 1);
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateWithdrawal);
        uint256 balanceBefore = address(this).balance;
        protocol.validateWithdrawal{ value: 0.5 ether }(currentPrice, "");
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
        protocol.updatePositionFees(0); // 0% fees

        bytes memory currentPrice = abi.encode(initialPrice);
        protocol.initiateWithdrawal(USDN_AMOUNT, currentPrice, "");

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        VaultPendingAction memory withdrawal = protocol.i_toVaultPendingAction(pending);

        uint256 vaultBalance = protocol.balanceVault(); // save for withdrawn amount calculation in case price decreases

        // wait the required delay between initiation and validation
        uint256 validationDelay = oracleMiddleware.validationDelay();
        skip(validationDelay + 1);

        currentPrice = abi.encode(assetPrice);

        // if price increases, we need to use the new balance to calculate the withdrawn amount
        if (assetPrice > initialPrice) {
            vaultBalance = uint256(protocol.vaultAssetAvailable(assetPrice));
        }

        PriceInfo memory withdrawalPrice =
            protocol.i_getOraclePrice(ProtocolAction.ValidateWithdrawal, withdrawal.timestamp, abi.encode(assetPrice));

        // Apply fees on price
        uint256 withdrawalPriceWithFees =
            withdrawalPrice.price - (withdrawalPrice.price * protocol.getPositionFee()) / protocol.BPS_DIVISOR();

        // We calculate the available balance of the vault side, either considering the asset price at the time of the
        // initiate action, or the current price provided for validation. We will use the lower of the two amounts to
        // redeem the underlying asset share.
        uint256 available1 = withdrawal.balanceVault;
        uint256 available2 = uint256(
            protocol.vaultAssetAvailable(
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

        // assetToTransfer = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        uint256 withdrawnAmount = FixedPointMathLib.fullMulDiv(withdrawal.amount, available, withdrawal.usdnTotalSupply);
        assertEq(withdrawnAmount, expectedAssetAmount, "asset amount");

        vm.expectEmit();
        emit ValidatedWithdrawal(address(this), withdrawnAmount, USDN_AMOUNT); // expected event
        protocol.validateWithdrawal(currentPrice, "");

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "final usdn balance");
        assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance + withdrawnAmount, "final wstETH balance");
    }

    // test refunds
    receive() external payable { }
}
