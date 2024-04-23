// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import {
    PendingAction,
    ProtocolAction,
    Position,
    DepositPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The deposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolDeposit is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;

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
     * @custom:scenario The user initiates a deposit of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's wstETH balance decreases by 1 wstETH
     * @custom:and The user's SDEX balance decreases by 20 SDEX
     * @custom:and The dead address's SDEX balance increases by 20 SDEX
     * @custom:and The protocol's wstETH balance increases by 1 wstETH
     * @custom:and The protocol emits an `InitiatedDeposit` event
     * @custom:and The USDN total supply does not change yet
     * @custom:and The user has a pending action of type `ValidateDeposit` with the amount of 1 wstETH
     * @custom:and The pending action is not actionable yet
     * @custom:and The pending action is actionable after the validation deadline has elapsed
     */
    function test_initiateDeposit() public {
        uint128 depositAmount = 1 ether;
        uint128 price = 2000 ether;
        bytes memory currentPrice = abi.encode(price); // only used to apply PnL + funding
        uint256 usdnToMint =
            protocol.i_calcMintUsdn(depositAmount, protocol.getBalanceVault(), protocol.getUsdn().totalSupply(), price);
        uint256 expectedSdexBurnAmount = protocol.i_calcSdexToBurn(usdnToMint, protocol.getSdexBurnOnDepositRatio());
        uint256 sdexBalanceBefore = sdex.balanceOf(address(this));
        address deadAddress = protocol.DEAD_ADDRESS();

        vm.expectEmit(address(sdex));
        emit Transfer(address(this), deadAddress, expectedSdexBurnAmount); // SDEX transfer
        vm.expectEmit();
        emit InitiatedDeposit(address(this), depositAmount, block.timestamp);
        protocol.initiateDeposit(depositAmount, currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(wstETH.balanceOf(address(this)), INITIAL_WSTETH_BALANCE - depositAmount, "wstETH user balance");
        assertEq(
            sdexBalanceBefore - expectedSdexBurnAmount,
            sdex.balanceOf(address(this)),
            "The amount of SDEX tokens to be burned should have been subtracted from the balance of the user"
        );
        assertEq(
            sdex.balanceOf(deadAddress),
            expectedSdexBurnAmount,
            "The amount of SDEX tokens to be burned should have been sent to the dead address"
        );
        assertEq(
            wstETH.balanceOf(address(protocol)),
            params.initialDeposit + params.initialLong + depositAmount,
            "wstETH protocol balance"
        );
        // no USDN should be minted yet
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply, "usdn total supply");
        // the pending action should not yet be actionable by a third party
        (PendingAction[] memory actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions.length, 0, "no pending action");

        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertTrue(action.action == ProtocolAction.ValidateDeposit, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.user, address(this), "action user");
        assertEq(action.amount, depositAmount, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions[0].user, address(this), "pending action user");
    }

    /**
     * @custom:scenario The user initiates a deposit of 0 wstETH
     * @custom:when The user initiates a deposit of 0 wstETH
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        bytes memory priceData = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateDeposit(0, priceData, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates a small deposit and no USDN would be minted
     * @custom:given The price of wstETH is $0.1
     * @custom:when The user initiates a deposit of 9 wei of wstETH
     * @custom:then The protocol reverts with `UsdnProtocolDepositTooSmall`
     */
    function test_RevertWhen_depositTooSmallNoUSDN() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = 0.1 ether;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);

        uint128 deposited = 9;

        uint256 usdnToMintEstimated =
            protocol.i_calcMintUsdn(deposited, protocol.getBalanceVault(), usdn.totalSupply(), params.initialPrice);
        assertEq(usdnToMintEstimated, 0, "usdn minted");

        vm.expectRevert(UsdnProtocolDepositTooSmall.selector);
        protocol.initiateDeposit(deposited, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates a small deposit and no SDEX would be burned
     * @custom:given The price of wstETH is $1
     * @custom:and The SDEX burn on deposit is enabled at 1% of the minted USDN
     * @custom:when The user initiates a deposit of 99 wei of wstETH
     * @custom:then The protocol would mint more than 0 USDN
     * @custom:and The protocol would burn 0 SDEX
     * @custom:and The protocol reverts with `UsdnProtocolDepositTooSmall`
     */
    function test_RevertWhen_depositTooSmallNoSDEXBurned() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = 1 ether;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);

        uint128 deposited = 99;

        uint256 usdnToMintEstimated =
            protocol.i_calcMintUsdn(deposited, protocol.getBalanceVault(), usdn.totalSupply(), params.initialPrice);
        assertGt(usdnToMintEstimated, 0, "usdn minted");

        uint256 sdexToBurn = protocol.i_calcSdexToBurn(usdnToMintEstimated, protocol.getSdexBurnOnDepositRatio());
        assertEq(sdexToBurn, 0, "sdex burned");

        vm.expectRevert(UsdnProtocolDepositTooSmall.selector);
        protocol.initiateDeposit(deposited, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario The user initiates a small deposit and SDEX burn is disabled
     * @custom:given The price of wstETH is $1
     * @custom:and The SDEX burn on deposit is disabled
     * @custom:when The user initiates a deposit of 99 wei of wstETH
     * @custom:then The protocol would mint more than 0 USDN
     * @custom:and The transaction does not revert
     */
    function test_smallDepositSDEXBurnDisabled() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = 1 ether;
        params.flags.enableSdexBurnOnDeposit = false;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);

        uint128 deposited = 99;

        uint256 usdnToMintEstimated =
            protocol.i_calcMintUsdn(deposited, protocol.getBalanceVault(), usdn.totalSupply(), params.initialPrice);
        assertGt(usdnToMintEstimated, 0, "usdn minted");

        protocol.initiateDeposit(deposited, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
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
        _checkValidateDepositWithPrice(2000 ether, 2100 ether, 2000 ether);
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
        _checkValidateDepositWithPrice(2000 ether, 1900 ether, 1900 ether);
    }

    /**
     * @custom:scenario The user sends too much ether when initiating a deposit
     * @custom:given The user deposits 1 wstETH
     * @custom:when The user sends 0.5 ether as value in the `initiateDeposit` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_initiateDepositEtherRefund() public {
        oracleMiddleware.setRequireValidationCost(true); // require 1 wei per validation
        uint256 balanceBefore = address(this).balance;
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        uint256 validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.InitiateDeposit);
        protocol.initiateDeposit{ value: 0.5 ether }(1 ether, currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
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
        protocol.initiateDeposit{ value: validationCost }(1 ether, currentPrice, EMPTY_PREVIOUS_DATA);

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateDeposit);
        assertEq(validationCost, 1);
        uint256 balanceBefore = address(this).balance;
        protocol.validateDeposit{ value: 0.5 ether }(currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The initial open position and a user open position are opened. The price drop and all positions
     * can be liquidated.
     * The first `initiateDeposit` liquidate the initial open position but isn't validated as a position must always be
     * liquidated.
     * The second `initiateDeposit` liquidate the remaining user open position and can be validated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drop below all position liquidation price
     * @custom:when The first `initiateDeposit` is called
     * @custom:and The initial open position is liquidated
     * @custom:and The user open position still need to be liquidated
     * @custom:and The user deposit isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateDeposit` is called
     * @custom:and The remaining user open position is liquidated
     * @custom:and No more position needs to be liquidated
     * @custom:and The user deposit is validated
     * @custom:then The transaction is completed
     */
    function test_depositIsPendingLiquidation() public {
        uint128 amount = 10 ether;

        // initial open position
        uint128 initialLiqPriceWithoutPenalty = (params.initialPrice / 2)
            + params.initialPrice / 2 * uint128(protocol.getProtocolFeeBps()) / uint128(protocol.BPS_DIVISOR());
        int24 initialPosTick = protocol.getEffectiveTickForPrice(initialLiqPriceWithoutPenalty)
            + int24(int8(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        uint256 initialPosTickVersion = protocol.getTickVersion(initialPosTick);

        // user open position
        (int24 userPosTick, uint256 userPosTickVersion,) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, amount, params.initialPrice / 4, params.initialPrice
        );

        assertTrue(initialPosTick != userPosTick, "same tick");

        skip(30 minutes - oracleMiddleware.getValidationDelay());

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(USER_1);
            uint256 balanceUSDNBefore = usdn.balanceOf(USER_1);
            uint256 balanceETHBefore = USER_1.balance;

            // should liquidate initial position
            // should not being validated because a position still need to be liquidated
            // should not revert
            vm.prank(USER_1);
            protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
                amount, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            assertEq(balanceETHBefore, USER_1.balance, "user loss eth");
            assertEq(wstethBalanceBefore, wstETH.balanceOf(USER_1), "user loss wsteth");
            assertEq(balanceUSDNBefore, usdn.balanceOf(USER_1), "user received usdn");
            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );
            assertEq(userPosTickVersion, protocol.getTickVersion(userPosTick), "user position is liquidated");
        }

        skip(30 minutes - oracleMiddleware.getValidationDelay());

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(USER_1);
            uint256 balanceUSDNBefore = usdn.balanceOf(USER_1);

            // mint more sdex to user
            sdex.mintAndApprove(USER_1, 1_000_000 ether, address(protocol), type(uint256).max);

            // should liquidate user position
            // should be validated because no more position need to be liquidated
            // should not revert
            PendingAction memory pendingAction =
                setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, amount, params.initialPrice / 10);

            DepositPendingAction memory depositPendingAction = protocol.i_toDepositPendingAction(pendingAction);

            uint256 expectedUSDN = protocol.i_calcMintUsdn(
                depositPendingAction.amount,
                uint256(
                    protocol.i_vaultAssetAvailable(
                        depositPendingAction.totalExpo,
                        depositPendingAction.balanceVault,
                        depositPendingAction.balanceLong,
                        uint128(
                            params.initialPrice / 10
                                - (params.initialPrice / 10 * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()
                        ),
                        depositPendingAction.assetPrice
                    )
                ),
                depositPendingAction.usdnTotalSupply,
                uint128(
                    params.initialPrice / 10
                        - (params.initialPrice / 10 * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()
                )
            );

            assertEq(wstethBalanceBefore, wstETH.balanceOf(USER_1), "user kept wsteth");
            assertEq(balanceUSDNBefore + expectedUSDN, usdn.balanceOf(USER_1), "wrong usdn amount received");
            assertEq(userPosTickVersion + 1, protocol.getTickVersion(userPosTick), "user position is not liquidated");
        }
    }

    /**
     * @custom:scenario The initial open position and a user open position are opened. The price drop and all positions
     * can be liquidated.
     * The first `initiateDeposit` liquidate the initial open position but isn't validated as a position must always be
     * liquidated.
     * The second `initiateDeposit` liquidate the remaining user open position and can be validated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drop below all position liquidation price
     * @custom:when The first `initiateDeposit` is called
     * @custom:and The initial open position is liquidated
     * @custom:and The user open position still need to be liquidated
     * @custom:and The user deposit isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateDeposit` is called
     * @custom:and The remaining user open position is liquidated
     * @custom:and No more position needs to be liquidated
     * @custom:and The user deposit is validated
     * @custom:then The transaction is completed
     */
    function test_depositSameBlockIsPendingLiquidation() public {
        uint128 amount = 10 ether;

        // initial open position
        uint128 initialLiqPriceWithoutPenalty = (params.initialPrice / 2)
            + params.initialPrice / 2 * uint128(protocol.getProtocolFeeBps()) / uint128(protocol.BPS_DIVISOR());
        int24 initialPosTick = protocol.getEffectiveTickForPrice(initialLiqPriceWithoutPenalty)
            + int24(int8(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        uint256 initialPosTickVersion = protocol.getTickVersion(initialPosTick);

        // user open position
        (int24 userPosTick, uint256 userPosTickVersion,) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, amount, params.initialPrice / 4, params.initialPrice
        );

        assertTrue(initialPosTick != userPosTick, "same tick");

        skip(30 minutes - oracleMiddleware.getValidationDelay());

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(USER_1);
            uint256 balanceUSDNBefore = usdn.balanceOf(USER_1);
            uint256 balanceETHBefore = USER_1.balance;

            vm.prank(USER_1);
            protocol.initiateDeposit{ value: protocol.getSecurityDepositValue() }(
                amount, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            assertEq(balanceETHBefore, USER_1.balance, "user loss eth");
            assertEq(wstethBalanceBefore, wstETH.balanceOf(USER_1), "user loss wsteth");
            assertEq(balanceUSDNBefore, usdn.balanceOf(USER_1), "user received usdn");
            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );
            assertEq(userPosTickVersion, protocol.getTickVersion(userPosTick), "user position is liquidated");
        }

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(USER_1);
            uint256 balanceUSDNBefore = usdn.balanceOf(USER_1);

            // mint more sdex to user
            sdex.mintAndApprove(USER_1, 1_000_000 ether, address(protocol), type(uint256).max);

            // should liquidate user position
            // should be validated because no more position need to be liquidated
            // should not revert
            PendingAction memory pendingAction =
                setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, amount, params.initialPrice);

            DepositPendingAction memory depositPendingAction = protocol.i_toDepositPendingAction(pendingAction);

            uint256 expectedUSDN = protocol.i_calcMintUsdn(
                depositPendingAction.amount,
                uint256(
                    protocol.i_vaultAssetAvailable(
                        depositPendingAction.totalExpo,
                        depositPendingAction.balanceVault,
                        depositPendingAction.balanceLong,
                        uint128(
                            params.initialPrice
                                - (params.initialPrice * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()
                        ),
                        depositPendingAction.assetPrice
                    )
                ),
                depositPendingAction.usdnTotalSupply,
                uint128(
                    params.initialPrice - (params.initialPrice * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()
                )
            );

            assertEq(userPosTickVersion + 1, protocol.getTickVersion(userPosTick), "user position is not liquidated");
            assertEq(wstethBalanceBefore, wstETH.balanceOf(USER_1), "user kept wsteth");
            assertEq(balanceUSDNBefore + expectedUSDN, usdn.balanceOf(USER_1), "wrong usdn amount received");
        }
    }

    /**
     * @dev Create a deposit at price `initialPrice`, then validate it at price `assetPrice`, then check the emitted
     * event and the resulting state.
     * @param initialPrice price of the asset at the time of deposit initiation
     * @param assetPrice price of the asset at the time of deposit validation
     * @param expectedUsdnAmount expected amount of USDN minted
     */
    function _checkValidateDepositWithPrice(uint128 initialPrice, uint128 assetPrice, uint256 expectedUsdnAmount)
        internal
    {
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(initialPrice); // only used to apply PnL + funding

        uint256 initiateDepositTimestamp = block.timestamp;
        vm.expectEmit();
        emit InitiatedDeposit(address(this), depositAmount, initiateDepositTimestamp); // expected event
        protocol.initiateDeposit(depositAmount, currentPrice, EMPTY_PREVIOUS_DATA);
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
        emit ValidatedDeposit(address(this), depositAmount, mintedAmount, initiateDepositTimestamp); // expected event
        protocol.validateDeposit(currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(usdn.balanceOf(address(this)), mintedAmount, "USDN user balance");
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + mintedAmount, "USDN total supply");
    }

    // test refunds
    receive() external payable { }
}
