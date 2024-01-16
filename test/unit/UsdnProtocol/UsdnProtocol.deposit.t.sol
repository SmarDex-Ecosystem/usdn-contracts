// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract TestUsdnProtocolDeposit is UsdnProtocolBaseFixture {
    uint256 constant INITIAL_WSTETH_BALANCE = 10 ether;

    function setUp() public override {
        super.setUp();
        wstETH.mint(address(this), INITIAL_WSTETH_BALANCE);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    function test_initiateDeposit() public {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        vm.expectEmit();
        emit InitiatedDeposit(address(this), depositAmount); // expected event
        protocol.initiateDeposit(depositAmount, currentPrice, "");

        assertEq(wstETH.balanceOf(address(this)), INITIAL_WSTETH_BALANCE - depositAmount, "wstETH user balance");
        assertEq(
            wstETH.balanceOf(address(protocol)),
            INITIAL_DEPOSIT + INITIAL_LONG + depositAmount,
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
        assertEq(action.amountOrIndex, depositAmount, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.validationDeadline() + 1);
        action = protocol.getActionablePendingAction(0);
        assertEq(action.user, address(this), "pending action user");
    }

    function test_RevertWhen_zeroAmount() public {
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateDeposit(0, abi.encode(uint128(2000 ether)), "");
    }

    function test_validateDepositPriceIncrease() public {
        // price increases from $2000 to $2100 between initiation and validation
        checkValidateDepositWithPrice(2000 ether, 2100 ether);
    }

    function test_validateDepositPriceDecrease() public {
        // price decreases from $2000 to $1900 between initiation and validation
        checkValidateDepositWithPrice(2000 ether, 1900 ether);
    }

    /**
     * Create a deposit at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted event
     * and the resulting state.
     * @param initialPrice price of the asset at the time of deposit initiation
     * @param assetPrice price of the asset at the time of deposit validation
     */
    function checkValidateDepositWithPrice(uint128 initialPrice, uint128 assetPrice) internal {
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(initialPrice); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, "");
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

        vm.expectEmit(true, true, false, false);
        emit ValidatedDeposit(address(this), depositAmount, mintedAmount); // expected event
        protocol.validateDeposit(currentPrice, "");

        assertEq(usdn.balanceOf(address(this)), mintedAmount, "USDN user balance");
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + mintedAmount, "USDN total supply");
    }
}
