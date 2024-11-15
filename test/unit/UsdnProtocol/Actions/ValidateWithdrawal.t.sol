// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ReentrancyGuardTransientUpgradeable } from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { ADMIN, DEPLOYER, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

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

    struct TestData {
        uint128 validatePrice;
        int24 validateTick;
        uint8 originalLiqPenalty;
        int24 tempTick;
        uint256 tempTickVersion;
        uint256 tempIndex;
        uint256 validateTickVersion;
        uint256 validateIndex;
        uint128 expectedLeverage;
    }

    struct TestData2 {
        bytes currentPrice;
        bytes32 actionId;
        WithdrawalPendingAction withdrawal;
        uint256 vaultBalance;
    }

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = 2000 ether; // fix the price to avoid future fixtures changes affecting these tests
        super._setUp(params);
        withdrawShares = USDN_AMOUNT * uint152(usdn.MAX_DIVISOR());
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at $2000
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, params.initialPrice);
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
    function test_withdrawSetUp() public view {
        // Using the price computed with the default position fees
        assertEq(initialUsdnBalance, 2000 * DEPOSIT_AMOUNT, "initial usdn balance");
        assertEq(initialUsdnShares, 2000 * DEPOSIT_AMOUNT * usdn.MAX_DIVISOR(), "initial usdn shares");
        assertEq(initialWstETHBalance, 0, "initial wstETH balance");
    }

    /**
     * @custom:scenario A validate withdrawal liquidates a tick but is not validated because another tick still needs
     * to be liquidated
     * @custom:given Two user positions in different ticks
     * @custom:when The `validateWithdrawal` function is called with a price below the liquidation price of both
     * positions
     * @custom:then One position is liquidated
     * @custom:and The withdrawal action isn't validated
     * @custom:and The user's wsteth balance does not change
     */
    function test_validateWithdrawalWithPendingLiquidation() public {
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice - params.initialPrice / 5,
                price: params.initialPrice
            })
        );

        _waitMockMiddlewarePriceDelay();

        uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

        protocol.initiateWithdrawal(
            uint128(usdn.balanceOf(address(this))),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        bool success = protocol.validateWithdrawal(
            payable(address(this)), abi.encode(params.initialPrice / 3), EMPTY_PREVIOUS_DATA
        );
        assertFalse(success, "success");

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(
            uint256(pending.action),
            uint256(ProtocolAction.ValidateWithdrawal),
            "user 0 pending action should not have been cleared"
        );

        assertEq(
            userPosId.tickVersion + 1,
            protocol.getTickVersion(userPosId.tick),
            "user 1 position should have been liquidated"
        );

        assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user 0 should not have gotten any wstETH");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price increases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $2500 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then Calculations use the lower validate vault balance
     * @custom:and The user's wstETH balance increases by 0.416891976723560318
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.416891976723560318
     */
    function test_validateWithdrawalPriceUp() public {
        _checkValidateWithdrawalWithPrice(uint128(2500 ether), 0.416891976723560318 ether, address(this));
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price increases so much the vault
     * balance becomes negative
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $10 000 at the moment of validation
     * @custom:and A user opened a long position of 10ETH with a 2.5x leverage
     * @custom:when The user validates the withdrawal
     * @custom:then The user's wstETH balance increases by 0
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 00
     */
    function test_validateWithdrawalPriceUpEmptyingVault() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 10 ether,
                desiredLiqPrice: 1000 ether,
                price: params.initialPrice
            })
        );

        _checkValidateWithdrawalWithPrice(uint128(10_000 ether), 0, address(this));
    }

    function test_validateWithdrawalWithNotEnoughFundsInVault() public {
        vm.prank(USER_1);
        usdn.approve(address(protocol), type(uint256).max);

        uint128 user1Amount = DEPOSIT_AMOUNT * 2;
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, user1Amount, params.initialPrice);
        uint256 user1Shares = usdn.sharesOf(USER_1);

        skip(1 hours);

        // initiate a withdrawal for USER_1 with the vault side in profit
        bytes memory currentPrice = abi.encode(params.initialPrice * 9 / 10);
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateWithdrawal);
        vm.prank(USER_1);
        protocol.initiateWithdrawal{ value: validationCost }(
            uint152(user1Shares),
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            USER_1,
            type(uint256).max,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );

        skip(1 hours);

        // transfer the deployer's shares to address(this)
        vm.startPrank(DEPLOYER);
        usdn.transferShares(address(this), usdn.sharesOf(DEPLOYER));
        vm.stopPrank();

        // initiate and validate a withdrawal for address(this) with no profit
        currentPrice = abi.encode(params.initialPrice);
        protocol.initiateWithdrawal{ value: validationCost }(
            uint152(usdn.sharesOf(address(this))),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(this),
            type(uint256).max,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateWithdrawal{ value: validationCost }(payable(this), currentPrice, EMPTY_PREVIOUS_DATA);

        // validate the withdrawal for USER_1 with the vault side at the same amount of profit than the initiate
        _waitDelay();

        assertGt(
            protocol.i_calcAmountToWithdraw(
                user1Shares,
                protocol.vaultAssetAvailableWithFunding(params.initialPrice * 9 / 10, uint128(block.timestamp)),
                usdn.totalShares(),
                protocol.getVaultFeeBps()
            ),
            protocol.getBalanceVault(),
            "The amount of assets withdrawn must be greater than the balance of the vault"
        );
        currentPrice = abi.encode(params.initialPrice * 9 / 10);
        protocol.validateWithdrawal{ value: validationCost }(USER_1, currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(protocol.getBalanceVault(), 0, "The withdrawal should have emptied the vault");
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN while the price decreases
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $1500 at the moment of validation
     * @custom:when The user validates the withdrawal
     * @custom:then Calculations use the lower initial balance
     * @custom:and The user's wstETH balance increases by 0.5
     * @custom:and The USDN total supply decreases by 1000
     * @custom:and The protocol emits a `ValidatedWithdrawal` event with the withdrawn amount of 0.5
     */
    function test_validateWithdrawalPriceDown() public {
        _checkValidateWithdrawalWithPrice(uint128(1500 ether), 0.5 ether, address(this));
    }

    /**
     * @custom:scenario The user validates a withdrawal for 1000 USDN with another address as the beneficiary
     * @custom:given The user initiated a withdrawal for 1000 USDN
     * @custom:and The price of the asset is $2000 at the moment of initiation and validation
     * @custom:when The user validates the withdrawal with another address as the beneficiary
     * @custom:then The protocol emits a `ValidatedWithdrawal` event with the right beneficiary
     */
    function test_validateWithdrawalDifferentToAddress() public {
        _checkValidateWithdrawalWithPrice(uint128(2000 ether), 0.5 ether, USER_1);
    }

    /**
     * @custom:scenario The user sends too much ether when validating a withdrawal
     * @custom:given The user initiated a withdrawal of 1000 USDN and validates it
     * @custom:when The user sends 0.5 ether as value in the `validateWithdrawal` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_validateWithdrawalEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        // initiate
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateWithdrawal);
        protocol.initiateWithdrawal{ value: validationCost }(
            USDN_AMOUNT,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateWithdrawal);
        uint256 balanceBefore = address(this).balance;
        protocol.validateWithdrawal{ value: 0.5 ether }(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @dev Create a withdrawal at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted
     * event and the resulting state.
     * @param assetPrice price of the asset at the time of withdrawal validation
     * @param expectedAssetAmount expected amount of asset withdrawn
     */
    function _checkValidateWithdrawalWithPrice(uint128 assetPrice, uint256 expectedAssetAmount, address to) public {
        TestData2 memory data;

        data.currentPrice = abi.encode(params.initialPrice);
        protocol.initiateWithdrawal(
            withdrawShares,
            DISABLE_AMOUNT_OUT_MIN,
            to,
            payable(address(this)),
            type(uint256).max,
            data.currentPrice,
            EMPTY_PREVIOUS_DATA
        );

        data.actionId = oracleMiddleware.lastActionId();
        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        data.withdrawal = protocol.i_toWithdrawalPendingAction(pending);

        // wait the required delay between initiation and validation
        _waitDelay();

        data.currentPrice = abi.encode(assetPrice);
        int256 vaultAssetAvailable = protocol.i_vaultAssetAvailable(
            data.withdrawal.totalExpo,
            data.withdrawal.balanceVault,
            data.withdrawal.balanceLong,
            assetPrice,
            protocol.getLastPrice()
        );
        if (vaultAssetAvailable < 0) {
            vaultAssetAvailable = 0;
        }
        uint256 available = uint256(vaultAssetAvailable);
        if (data.withdrawal.balanceVault < available) {
            available = data.withdrawal.balanceVault;
        }

        uint256 shares = protocol.i_mergeWithdrawalAmountParts(data.withdrawal.sharesLSB, data.withdrawal.sharesMSB);
        uint256 withdrawnAmount = FixedPointMathLib.fullMulDiv(shares, available, data.withdrawal.usdnTotalShares);
        uint256 withdrawnAmountWithFees = withdrawnAmount - (withdrawnAmount * data.withdrawal.feeBps) / BPS_DIVISOR;
        assertEq(withdrawnAmountWithFees, expectedAssetAmount, "asset amount");

        vm.expectEmit();
        emit ValidatedWithdrawal(to, address(this), withdrawnAmountWithFees, USDN_AMOUNT, data.withdrawal.timestamp);
        bool success = protocol.validateWithdrawal(payable(address(this)), data.currentPrice, EMPTY_PREVIOUS_DATA);
        assertTrue(success, "success");
        assertEq(oracleMiddleware.lastActionId(), data.actionId, "middleware action ID");

        assertEq(usdn.balanceOf(address(this)), initialUsdnBalance - USDN_AMOUNT, "final usdn balance");
        if (to == address(this)) {
            assertEq(wstETH.balanceOf(to), initialWstETHBalance + withdrawnAmountWithFees, "final wstETH balance");
        } else {
            assertEq(wstETH.balanceOf(to), withdrawnAmountWithFees, "final wstETH balance");
            assertEq(wstETH.balanceOf(address(this)), initialWstETHBalance, "final wstETH balance");
        }

        PendingAction memory emptyPendingAction;
        (PendingAction memory pendingAction,) = protocol.i_getPendingAction(address(this));
        assertEq(
            abi.encode(pendingAction), abi.encode(emptyPendingAction), "The pending action should have been cleared"
        );
    }

    /**
     * @custom:scenario The user validates a withdrawal action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls validateWithdrawal with too much ether
     * @custom:and A receive() function that calls validateWithdrawal again
     * @custom:when The user calls validateWithdrawal again from the callback
     * @custom:then The call reverts with ReentrancyGuardReentrantCall
     */
    function test_RevertWhen_validateWithdrawalCalledWithReentrancy() public {
        bytes memory currentPrice = abi.encode(params.initialPrice);

        if (_reenter) {
            vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector);
            protocol.validateWithdrawal(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
            return;
        }

        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, DEPOSIT_AMOUNT, params.initialPrice);

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.validateWithdrawal.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.validateWithdrawal{ value: 1 }(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario A user tries to validate a withdrawal action with the wrong pending action
     * @custom:given An initiated open position
     * @custom:when The owner of the position calls _validateWithdrawal
     * @custom:then The call reverts because the pending action is not of type ValidateWithdrawal
     */
    function test_RevertWhen_validateWithdrawalWithTheWrongPendingAction() public {
        // Setup an initiate action to have a pending validate action for this user
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: DEFAULT_PARAMS.initialPrice / 2,
                price: DEFAULT_PARAMS.initialPrice
            })
        );

        bytes memory priceData = abi.encode(DEFAULT_PARAMS.initialPrice);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidPendingAction.selector));
        protocol.i_validateWithdrawal(address(this), priceData);
    }

    /**
     * @custom:scenario The user validates a withdrawal pending action that has a different validator
     * @custom:given A pending action of type ValidateWithdrawal
     * @custom:and With a validator that is not the caller saved at the caller's address
     * @custom:when The user calls validateWithdrawal
     * @custom:then The protocol reverts with a UsdnProtocolInvalidPendingAction error
     */
    function test_RevertWhen_validateWithdrawalWithWrongValidator() public {
        bytes memory currentPrice = abi.encode(params.initialPrice);
        protocol.initiateWithdrawal(
            withdrawShares,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );

        // update the pending action to put another validator
        (PendingAction memory pendingAction, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        pendingAction.validator = address(1);

        protocol.i_clearPendingAction(address(this), rawIndex);
        protocol.i_addPendingAction(address(this), pendingAction);

        vm.expectRevert(UsdnProtocolInvalidPendingAction.selector);
        protocol.i_validateWithdrawal(payable(address(this)), currentPrice);
    }

    /**
     * @custom:scenario The user initiates and validates (after the validator deadline)
     * a withdraw with another validator
     * @custom:given The user initiated a withdraw of 1000 usdn and validates it
     * @custom:and we wait until the validation deadline is passed
     * @custom:when The user validates the withdraw
     * @custom:then The security deposit is refunded to the validator
     */
    function test_validateWithdrawalEtherRefundToValidator() public {
        vm.startPrank(ADMIN);
        protocol.setSecurityDepositValue(0.5 ether);
        vm.stopPrank();

        bytes memory currentPrice = abi.encode(params.initialPrice);

        uint64 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 balanceUserBefore = USER_1.balance;
        uint256 balanceContractBefore = address(this).balance;

        protocol.initiateWithdrawal{ value: 0.5 ether }(
            withdrawShares,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            USER_1,
            type(uint256).max,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();
        protocol.validateWithdrawal(USER_1, currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(USER_1.balance, balanceUserBefore + securityDepositValue, "user balance after refund");
        assertEq(address(this).balance, balanceContractBefore - securityDepositValue, "contract balance after refund");
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
