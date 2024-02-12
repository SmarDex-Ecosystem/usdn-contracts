// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature The `deposit` function of the USDN Protocol
 * @custom:background Given a protocol initialized with 10 wstETH in the vault and 5 wstETH in a long position with a
 * leverage of ~2x.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolDeposit is UsdnProtocolBaseFixture {
    uint256 constant INITIAL_WSTETH_BALANCE = 10 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mint(address(this), INITIAL_WSTETH_BALANCE);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's wstETH balance decreases by 1 wstETH
     * @custom:and The protocol's wstETH balance increases by 1 wstETH
     * @custom:and The protocol emits an `InitiatedDeposit` event
     * @custom:and The USDN total supply does not change yet
     * @custom:and The user has a pending action of type `InitiateDeposit` with the amount of 1 wstETH
     * @custom:and The pending action is not actionable yet
     * @custom:and The pending action is actionable after the validation deadline has elapsed
     */
    function test_initiateDeposit() public {
        initiateDepositScenario(address(this));
    }

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH with another user as the beneficiary
     * @custom:given The to parameter is different from the sender of the transaction
     * @custom:when initiateDeposit function is called
     * @custom:then The protocol emits an `InitiatedDeposit` event with the right beneficiary
     * @custom:and The user has a pending action of type `InitiateDeposit` with the right beneficiary
     */
    function test_initiateDepositForAnotherUser() public {
        initiateDepositScenario(USER_1);
    }

    function initiateDepositScenario(address to) internal {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        vm.expectEmit();
        emit InitiatedDeposit(address(this), to, depositAmount); // expected event
        protocol.initiateDeposit(depositAmount, currentPrice, "", to);

        assertEq(wstETH.balanceOf(address(this)), INITIAL_WSTETH_BALANCE - depositAmount, "wstETH user balance");
        assertEq(
            wstETH.balanceOf(address(protocol)),
            params.initialDeposit + params.initialLong + depositAmount,
            "wstETH protocol balance"
        );
        // no USDN should be minted yet
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply, "usdn total supply");
        // the pending action should not yet be actionable by a third party
        PendingAction memory action = protocol.getActionablePendingAction(0);
        assertTrue(action.action == ProtocolAction.None, "no pending action");

        action = protocol.getUserPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.InitiateDeposit, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.to, to, "action to");
        assertEq(action.amountOrIndex, depositAmount, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.validationDeadline() + 1);
        action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(this), "pending action user");
    }

    /**
     * @custom:scenario The user initiates a deposit with parameter to defined at zero
     * @custom:when The user initiates a deposit with parameter to defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolZeroAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        vm.expectRevert(UsdnProtocolZeroAddressTo.selector);
        protocol.initiateDeposit(1 ether, abi.encode(uint128(2000 ether)), "", address(0));
    }

    /**
     * @custom:scenario The user initiates a deposit of 0 wstETH
     * @custom:when The user initiates a deposit of 0 wstETH
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateDeposit(0, abi.encode(uint128(2000 ether)), "", address(this));
    }

    /**
     * @custom:scenario The user initiates and validates a deposit while the price of the asset increases
     * @custom:given The user deposits 1 wstETH
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $2100 at the moment of validation
     * @custom:when The user validates the deposit
     * @custom:then The user's USDN balance increases by 2000 USDN
     * @custom:and The USDN total supply increases by 2000 USDN
     */
    function test_validateDepositPriceIncrease() public {
        checkValidateDepositWithPrice(2000 ether, 2100 ether, 2000 ether);
    }

    /**
     * @custom:scenario The user initiates and validates a deposit while the price of the asset decreases
     * @custom:given The user deposits 1 wstETH
     * @custom:and The price of the asset is $2000 at the moment of initiation
     * @custom:and The price of the asset is $1900 at the moment of validation
     * @custom:when The user validates the deposit
     * @custom:then The user's USDN balance increases by 1949.518048223628563225 USDN
     * @custom:and The USDN total supply increases by 1949.518048223628563225 USDN
     */
    function test_validateDepositPriceDecrease() public {
        checkValidateDepositWithPrice(2000 ether, 1900 ether, 1949.518048223628563225 ether);
    }

    /**
     * Create a deposit at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted event
     * and the resulting state.
     * @param initialPrice price of the asset at the time of deposit initiation
     * @param assetPrice price of the asset at the time of deposit validation
     * @param expectedUsdnAmount expected amount of USDN minted
     */
    function checkValidateDepositWithPrice(uint128 initialPrice, uint128 assetPrice, uint256 expectedUsdnAmount)
        internal
    {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(initialPrice); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, "", address(this));
        uint256 vaultBalance = protocol.balanceVault(); // save for mint amount calculation in case price increases

        // wait the required delay between initiation and validation
        uint256 validationDelay = oracleMiddleware.validationDelay();
        skip(validationDelay + 1);

        // set the effective price used for minting USDN
        currentPrice = abi.encode(assetPrice);

        // if price decreases, we need to use the new balance to calculate the minted amount
        if (assetPrice < 2000 ether) {
            vaultBalance = uint256(protocol.vaultAssetAvailable(assetPrice));
        }

        // theoretical minted amount
        uint256 mintedAmount = uint256(depositAmount) * usdn.totalSupply() / vaultBalance;
        assertEq(mintedAmount, expectedUsdnAmount, "minted amount");

        vm.expectEmit(true, true, false, false);
        emit ValidatedDeposit(address(this), depositAmount, mintedAmount); // expected event
        protocol.validateDeposit(currentPrice, "");

        assertEq(usdn.balanceOf(address(this)), mintedAmount, "USDN user balance");
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + mintedAmount, "USDN total supply");
    }
}
