// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { ADMIN, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The deposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsValidateDeposit is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;
    uint128 constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);

        // Sanity check
        assertGt(protocol.getSdexBurnOnDepositRatio(), 0, "USDN to SDEX burn ratio should not be 0");

        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario The user initiates and validates a deposit while the price of the asset increases
     * @custom:given The user deposits 1 wstETH
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $2100 at the moment of validation
     * @custom:when The user validates the deposit
     * @custom:then The user's USDN balance increases by 2000 USDN
     * @custom:and The USDN total supply increases by 2000 USDN
     * @custom:and The protocol emits a `ValidatedDeposit` event with the minted amount of 2000 USDN
     */
    function test_validateDepositPriceIncrease() public {
        _checkValidateDepositWithPrice(2000 ether, 2100 ether, 2000 ether, address(this));
    }

    /**
     * @custom:scenario The user initiates and validates a deposit while the price of the asset increases so much it
     * empties the vault
     * @custom:given The user deposits 1 wstETH
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $4000 at the moment of validation
     * @custom:and Another user opened a long position
     * @custom:when The user validates the deposit
     * @custom:then The user's USDN balance increases by 2000 USDN
     * @custom:and The USDN total supply increases by 2000 USDN
     * @custom:and The protocol emits a `ValidatedDeposit` event with the minted amount of 2000 USDN
     */
    function test_validateDepositPriceIncreaseEmptyingVault() public {
        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 10 ether,
                desiredLiqPrice: 1000 ether,
                price: params.initialPrice
            })
        );

        uint128 newPrice = 4000 ether;
        int256 vaultBalance = protocol.i_vaultAssetAvailable(newPrice);
        assertLt(vaultBalance, 0, "The assets available in the vault should be less than 0, try increasing `newPrice`");

        // - 407 because the previous long increased the vault balance by 1 wei
        _checkValidateDepositWithPrice(params.initialPrice, newPrice, 2000 ether - 407, address(this));
    }

    /**
     * @custom:scenario The user initiates and validates a deposit while the price of the asset decreases
     * @custom:given The user deposits 1 wstETH
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $1900 at the moment of validation
     * @custom:when The user validates the deposit
     * @custom:then The user's USDN balance increases by 1900 USDN
     * @custom:and The USDN total supply increases by 1900 USDN
     * @custom:and The protocol emits a `ValidatedDeposit` event with the minted amount of 1900 USDN
     */
    function test_validateDepositPriceDecrease() public {
        _checkValidateDepositWithPrice(2000 ether, 1900 ether, 1900 ether, address(this));
    }

    /**
     * @custom:scenario The user initiates and validates a deposit while to parameter is different from the user
     * @custom:given The user deposits 1 wstETH
     * @custom:and The price of the asset is $2000 at the moment of initiation and validation
     * @custom:when The user validates the deposit
     * @custom:and The USDN total supply increases by 2000 USDN
     * @custom:and The USDN balance increases by 2000 USDN for the address to
     * @custom:and The protocol emits a `ValidatedDeposit` event with the minted amount of 2000 USDN
     */
    function test_validateDepositForAnotherUser() public {
        _checkValidateDepositWithPrice(2000 ether, 2000 ether, 2000 ether, USER_1);
    }

    /**
     * @custom:scenario The user sends too much ether when validating a deposit
     * @custom:given The user initiated a deposit of 1 wstETH and validates it
     * @custom:when The user sends 0.5 ether as value in the `validateDeposit` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_validateDepositEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        // initiate
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateDeposit);
        assertEq(validationCost, 1);
        protocol.initiateDeposit{ value: validationCost }(
            DEPOSIT_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateDeposit);
        assertEq(validationCost, 1);
        uint256 balanceBefore = address(this).balance;
        protocol.validateDeposit{ value: 0.5 ether }(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario A validate deposit liquidates a tick but is not validated because another tick still needs to
     * be liquidated
     * @custom:given Two positions with different liquidation prices
     * @custom:and A user initiated a deposit action
     * @custom:when The `validateDeposit` function is called with a price below the liq price of both positions
     * @custom:then One of the positions is liquidated
     * @custom:and The deposit action isn't validated
     * @custom:and The user's usdn balance should not change
     */
    function test_validateDepositWithPendingLiquidation() public {
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

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

        protocol.initiateDeposit(
            DEPOSIT_AMOUNT,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        bool success =
            protocol.validateDeposit(payable(address(this)), abi.encode(params.initialPrice / 3), EMPTY_PREVIOUS_DATA);
        assertFalse(success, "success");

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(
            uint256(pending.action),
            uint256(ProtocolAction.ValidateDeposit),
            "user 0 pending action should not have been cleared"
        );

        assertEq(
            userPosId.tickVersion + 1,
            protocol.getTickVersion(userPosId.tick),
            "user 1 position should have been liquidated"
        );

        assertEq(usdnBalanceBefore, usdn.balanceOf(address(this)), "user 0 should not have gotten any USDN");
    }

    /**
     * @dev Create a deposit at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted
     * event and the resulting state.
     * @param initialPrice price of the asset at the time of deposit initiation
     * @param assetPrice price of the asset at the time of deposit validation
     * @param expectedUsdnAmount expected amount of USDN minted
     * @param to address the minted USDN will be sent to
     */
    function _checkValidateDepositWithPrice(
        uint128 initialPrice,
        uint128 assetPrice,
        uint256 expectedUsdnAmount,
        address to
    ) internal {
        bytes memory currentPrice = abi.encode(initialPrice); // only used to apply PnL + funding
        uint128 amountAfterFees =
            uint128(DEPOSIT_AMOUNT - uint256(DEPOSIT_AMOUNT) * protocol.getVaultFeeBps() / BPS_DIVISOR);
        uint256 usdnSharesToMint =
            Utils._calcMintUsdnShares(amountAfterFees, protocol.getBalanceVault(), protocol.getUsdn().totalShares());
        uint256 expectedSdexBurnAmount =
            protocol.i_calcSdexToBurn(usdn.convertToTokens(usdnSharesToMint), protocol.getSdexBurnOnDepositRatio());
        uint256 initiateDepositTimestamp = block.timestamp;

        vm.expectEmit();
        emit InitiatedDeposit(
            to,
            address(this),
            DEPOSIT_AMOUNT,
            protocol.getVaultFeeBps(),
            initiateDepositTimestamp,
            expectedSdexBurnAmount
        );
        protocol.initiateDeposit(
            DEPOSIT_AMOUNT, DISABLE_SHARES_OUT_MIN, to, payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA
        );
        uint256 vaultBalance = protocol.getBalanceVault(); // save for mint amount calculation in case price increases
        bytes32 actionId = oracleMiddleware.lastActionId();

        // wait the required delay between initiation and validation
        _waitDelay();

        // set the effective price used for minting USDN
        currentPrice = abi.encode(assetPrice);

        // if price decreases, we need to use the new balance to calculate the minted amount
        if (assetPrice < initialPrice) {
            vaultBalance = uint256(protocol.i_vaultAssetAvailable(assetPrice));
        }

        // theoretical minted amount
        uint256 mintedAmount = uint256(DEPOSIT_AMOUNT) * usdn.totalSupply() / vaultBalance;
        assertEq(mintedAmount, expectedUsdnAmount, "minted amount");

        vm.expectEmit();
        emit ValidatedDeposit(to, address(this), DEPOSIT_AMOUNT, mintedAmount, initiateDepositTimestamp);
        bool success = protocol.validateDeposit(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
        assertTrue(success, "success");

        assertEq(usdn.balanceOf(to), mintedAmount, "USDN to balance");
        if (address(this) != to) {
            assertEq(usdn.balanceOf(address(this)), 0, "USDN user balance");
        }
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + mintedAmount, "USDN total supply");
        assertEq(oracleMiddleware.lastActionId(), actionId, "middleware action ID");
    }

    /**
     * @custom:scenario A user tries to validate a deposit action with the wrong pending action
     * @custom:given An initiated open position
     * @custom:when The owner of the position calls _validateDeposit
     * @custom:then The call reverts because the pending action is not of type ValidateDeposit
     */
    function test_RevertWhen_validateDepositWithTheWrongPendingAction() public {
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

        bytes memory currentPrice = abi.encode(DEFAULT_PARAMS.initialPrice);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidPendingAction.selector));
        protocol.i_validateDeposit(payable(address(this)), currentPrice);
    }

    /**
     * @custom:scenario The user validates a deposit pending action that has a different validator
     * @custom:given A pending action of type ValidateDeposit
     * @custom:and With a validator that is not the caller saved at the caller's address
     * @custom:when The user calls validateDeposit
     * @custom:then The protocol reverts with a UsdnProtocolInvalidPendingAction error
     */
    function test_RevertWhen_validateDepositWithWrongValidator() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, DEPOSIT_AMOUNT, 2000 ether);

        // update the pending action to put another validator
        (PendingAction memory pendingAction, uint128 rawIndex) = protocol.i_getPendingAction(address(this));
        pendingAction.validator = address(1);

        protocol.i_clearPendingAction(address(this), rawIndex);
        protocol.i_addPendingAction(address(this), pendingAction);

        vm.expectRevert(UsdnProtocolInvalidPendingAction.selector);
        protocol.i_validateDeposit(payable(address(this)), currentPrice);
    }

    /**
     * @custom:scenario The user validates a deposit action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls validateDeposit with too much ether
     * @custom:and A receive() function that calls validateDeposit again
     * @custom:when The user calls validateDeposit again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_validateDepositCalledWithReentrancy() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.validateDeposit(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
            return;
        }

        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, DEPOSIT_AMOUNT, 2000 ether);

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.validateDeposit.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.validateDeposit{ value: 1 }(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates and validates (after the validator deadline)
     * a deposit with another validator
     * @custom:given The user initiated a deposit of 1 wstETH
     * @custom:and we wait until the validation deadline is passed
     * @custom:when The user validates the deposit
     * @custom:then The security deposit is refunded to the validator
     */
    function test_validateDepositEtherRefundToValidator() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        uint64 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 balanceUserBefore = USER_1.balance;
        uint256 balanceContractBefore = address(this).balance;

        protocol.initiateDeposit{ value: 0.5 ether }(
            DEPOSIT_AMOUNT, DISABLE_SHARES_OUT_MIN, address(this), USER_1, currentPrice, EMPTY_PREVIOUS_DATA
        );
        _waitBeforeActionablePendingAction();
        protocol.validateDeposit(USER_1, currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(USER_1.balance, balanceUserBefore + securityDepositValue, "user balance after refund");
        assertEq(address(this).balance, balanceContractBefore - securityDepositValue, "contract balance after refund");
    }

    /**
     * @custom:scenario The user validates a deposit with a paused protocol
     * @custom:given A pending deposit position
     * @custom:and A paused protocol
     * @custom:when The user calls validateDeposit
     * @custom:then The protocol reverts with a `EnforcedPause` error
     */
    function test_RevertWhen_validateDepositPaused() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, DEPOSIT_AMOUNT, 2000 ether);

        _pauseProtocol(ADMIN);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        protocol.validateDeposit(payable(this), currentPrice, EMPTY_PREVIOUS_DATA);
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_validateDepositCalledWithReentrancy();
            _reenter = false;
        }
    }
}
