// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The deposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsValidateDeposit is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 4.919970269703463156 ether; // same as long trading expo
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
            1 ether, currentPrice, EMPTY_PREVIOUS_DATA, address(this), address(this)
        );

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateDeposit);
        assertEq(validationCost, 1);
        uint256 balanceBefore = address(this).balance;
        protocol.validateDeposit{ value: 0.5 ether }(address(this), currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
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
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(initialPrice); // only used to apply PnL + funding

        uint256 initiateDepositTimestamp = block.timestamp;
        vm.expectEmit();
        emit InitiatedDeposit(to, address(this), depositAmount, initiateDepositTimestamp); // expected event
        protocol.initiateDeposit(depositAmount, currentPrice, EMPTY_PREVIOUS_DATA, to, address(this));
        uint256 vaultBalance = protocol.getBalanceVault(); // save for mint amount calculation in case price increases

        // wait the required delay between initiation and validation
        _waitDelay();

        // set the effective price used for minting USDN
        currentPrice = abi.encode(assetPrice);

        // if price decreases, we need to use the new balance to calculate the minted amount
        if (assetPrice < initialPrice) {
            vaultBalance = uint256(protocol.i_vaultAssetAvailable(assetPrice));
        }

        // theoretical minted amount
        uint256 mintedAmount = uint256(depositAmount) * usdn.totalSupply() / vaultBalance;
        assertEq(mintedAmount, expectedUsdnAmount, "minted amount");

        vm.expectEmit();
        emit ValidatedDeposit(to, address(this), depositAmount, mintedAmount, initiateDepositTimestamp); // expected
            // event
        protocol.validateDeposit(address(this), currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(usdn.balanceOf(to), mintedAmount, "USDN to balance");
        if (address(this) != to) {
            assertEq(usdn.balanceOf(address(this)), 0, "USDN user balance");
        }
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + mintedAmount, "USDN total supply");
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
            protocol.validateDeposit(address(this), currentPrice, EMPTY_PREVIOUS_DATA);
            return;
        }

        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, 2000 ether);

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.validateDeposit.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.validateDeposit{ value: 1 }(address(this), currentPrice, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates and validates (after the validationDeadline)
     * a deposit with another validator
     * @custom:given The user initiated a deposit of 1 wstETH
     * @custom:and we wait until the validation deadline is passed
     * @custom:when The user validates the deposit
     * @custom:then The security deposit is refunded to the validator
     */
    function test_validateDepositEtherRefundToValidator() public {
        vm.startPrank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees
        protocol.setSecurityDepositValue(0.5 ether);
        vm.stopPrank();

        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        uint64 securityDepositValue = protocol.getSecurityDepositValue();
        uint256 balanceUserBefore = USER_1.balance;
        uint256 balanceContractBefore = address(this).balance;

        protocol.initiateDeposit{ value: 0.5 ether }(1 ether, currentPrice, EMPTY_PREVIOUS_DATA, address(this), USER_1);
        _waitBeforeActionablePendingAction();
        protocol.validateDeposit(USER_1, currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(USER_1.balance, balanceUserBefore + securityDepositValue, "user balance after refund");
        assertEq(address(this).balance, balanceContractBefore - securityDepositValue, "contract balance after refund");
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
