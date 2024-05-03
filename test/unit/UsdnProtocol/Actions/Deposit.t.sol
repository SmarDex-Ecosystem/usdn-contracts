// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN, USER_1 } from "test/utils/Constants.sol";

import {
    PendingAction,
    ProtocolAction,
    Position,
    PositionId,
    DepositPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The deposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolDeposit is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant POSITION_AMOUNT = 1 ether;
    uint256 internal securityDeposit;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);

        // Sanity check
        assertGt(protocol.getSdexBurnOnDepositRatio(), 0, "USDN to SDEX burn ratio should not be 0");

        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);
        securityDeposit = protocol.getSecurityDepositValue();
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
        _initiateDepositScenario(address(this));
    }

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH with another user as the beneficiary
     * @custom:given The to parameter is different from the sender of the transaction
     * @custom:when initiateDeposit function is called
     * @custom:then The protocol emits an `InitiatedDeposit` event with the right beneficiary
     * @custom:and The user has a pending action of type `InitiateDeposit` with the right beneficiary
     */
    function test_initiateDepositForAnotherUser() public {
        _initiateDepositScenario(USER_1);
    }

    function _initiateDepositScenario(address to) internal {
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
        emit InitiatedDeposit(address(this), to, depositAmount, block.timestamp);
        protocol.initiateDeposit(depositAmount, currentPrice, EMPTY_PREVIOUS_DATA, to);

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
        assertEq(action.to, to, "action to");
        assertEq(action.var2, depositAmount, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions[0].user, address(this), "pending action user");
    }

    /**
     * @custom:scenario The user initiates a deposit with parameter to defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates a deposit with parameter to defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.initiateDeposit(1 ether, abi.encode(uint128(2000 ether)), EMPTY_PREVIOUS_DATA, address(0));
    }

    /**
     * @custom:scenario The user initiates a deposit of 0 wstETH
     * @custom:when The user initiates a deposit of 0 wstETH
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        bytes memory priceData = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateDeposit(0, priceData, EMPTY_PREVIOUS_DATA, address(this));
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
        protocol.initiateDeposit(deposited, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this));
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
        protocol.initiateDeposit(deposited, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this));
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
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);

        uint128 deposited = 99;

        uint256 usdnToMintEstimated =
            protocol.i_calcMintUsdn(deposited, protocol.getBalanceVault(), usdn.totalSupply(), params.initialPrice);
        assertGt(usdnToMintEstimated, 0, "usdn minted");

        protocol.initiateDeposit(deposited, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this));
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
        protocol.initiateDeposit{ value: 0.5 ether }(1 ether, currentPrice, EMPTY_PREVIOUS_DATA, address(this));
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
        protocol.initiateDeposit{ value: validationCost }(1 ether, currentPrice, EMPTY_PREVIOUS_DATA, address(this));

        _waitDelay();
        // validate
        validationCost = oracleMiddleware.validationCost(currentPrice, ProtocolAction.ValidateDeposit);
        assertEq(validationCost, 1);
        uint256 balanceBefore = address(this).balance;
        protocol.validateDeposit{ value: 0.5 ether }(currentPrice, EMPTY_PREVIOUS_DATA);
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario A initiate deposit liquidates a pending tick but is not validated
     * because a tick still need to be liquidated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drop below all position liquidation prices
     * @custom:when The first `initiateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still need to be liquidated
     * @custom:and The user deposit isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateDeposit` is called
     * @custom:and The user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user deposit is validated
     * @custom:then The transaction is completed
     */
    function test_initiateDepositIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user open position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                POSITION_AMOUNT,
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateDeposit{ value: securityDeposit }(
                POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action is initiated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");

            assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user loss wsteth");
        }

        _waitMockMiddlewarePriceDelay();

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateDeposit{ value: securityDeposit }(
                POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action is not initiated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertGt(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user kept wsteth");
        }
    }

    /**
     * @custom:scenario A initiate deposit liquidates a tick but is not validated
     * because a tick still need to be liquidated. In the same block another deposit
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drop below all position liquidation prices
     * @custom:when The first `initiateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still need to be liquidated
     * @custom:and The user deposit isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `initiateDeposit` is called in the same block
     * @custom:and The user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user deposit is validated
     * @custom:then The transaction is completed
     */
    function test_initiateDepositSameBlockIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user open position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                POSITION_AMOUNT,
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateDeposit{ value: securityDeposit }(
                POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action is initiated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");

            assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user loss wsteth");
        }

        {
            uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

            protocol.initiateDeposit{ value: securityDeposit }(
                POSITION_AMOUNT, abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action is not initiated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertGt(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user kept wsteth");
        }
    }

    /**
     * @custom:scenario A validate deposit liquidates a pending tick but is not validated
     * because a tick still need to be liquidated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and A user initiateDeposit position is pending
     * @custom:and The price drop below all position liquidation prices
     * @custom:when The first `validateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still need to be liquidated
     * @custom:and The user deposit isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `validateDeposit` is called
     * @custom:and The user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user deposit is validated
     * @custom:then The transaction is completed
     */
    function test_validateDepositIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user open position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                POSITION_AMOUNT,
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

            protocol.initiateDeposit{ value: securityDeposit }(
                POSITION_AMOUNT, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action was validated");

            _waitDelay();

            protocol.validateDeposit{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action was validated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");

            assertEq(usdnBalanceBefore, usdn.balanceOf(address(this)), "user usdn balance increased");
        }

        _waitMockMiddlewarePriceDelay();

        {
            uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

            protocol.validateDeposit{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action was not validated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertLt(usdnBalanceBefore, usdn.balanceOf(address(this)), "user usdn balance is lower or equal");
        }
    }

    /**
     * @custom:scenario A validate deposit liquidates a tick but is not validated
     * because a tick still need to be liquidated. In the same block another deposit
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drop below all position liquidation prices
     * @custom:when The first `validateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still need to be liquidated
     * @custom:and The user deposit isn't validated
     * @custom:then The transaction is completed
     * @custom:when The second `validateDeposit` is called in the same block
     * @custom:and The user open position tick is liquidated
     * @custom:and No more tick needs to be liquidated
     * @custom:and The user deposit is validated
     * @custom:then The transaction is completed
     */
    function test_validateDepositSameBlockIsPendingLiquidation() public {
        // initial open position
        (int24 initialPosTick, uint256 initialPosTickVersion) = _getInitialLongPosition();

        // user open position
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams(
                USER_1,
                ProtocolAction.ValidateOpenPosition,
                POSITION_AMOUNT,
                params.initialPrice / 4,
                params.initialPrice
            )
        );

        _waitMockMiddlewarePriceDelay();

        {
            uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

            protocol.initiateDeposit{ value: securityDeposit }(
                POSITION_AMOUNT, abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA, address(this)
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action was validated");

            _waitDelay();

            protocol.validateDeposit{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action was validated");

            assertEq(
                initialPosTickVersion + 1, protocol.getTickVersion(initialPosTick), "initial position is not liquidated"
            );

            assertEq(userPosId.tickVersion, protocol.getTickVersion(userPosId.tick), "user position is liquidated");

            assertEq(usdnBalanceBefore, usdn.balanceOf(address(this)), "user usdn balance increased");
        }

        {
            uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

            protocol.validateDeposit{ value: securityDeposit }(
                abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action was not validated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertLt(usdnBalanceBefore, usdn.balanceOf(address(this)), "user usdn balance is lower or equal");
        }
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
        emit InitiatedDeposit(address(this), to, depositAmount, initiateDepositTimestamp); // expected event
        protocol.initiateDeposit(depositAmount, currentPrice, EMPTY_PREVIOUS_DATA, to);
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
        emit ValidatedDeposit(address(this), to, depositAmount, mintedAmount, initiateDepositTimestamp); // expected
            // event
        protocol.validateDeposit(currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(usdn.balanceOf(to), mintedAmount, "USDN to balance");
        if (address(this) != to) {
            assertEq(usdn.balanceOf(address(this)), 0, "USDN user balance");
        }
        assertEq(usdn.totalSupply(), usdnInitialTotalSupply + mintedAmount, "USDN total supply");
    }

    // test refunds
    receive() external payable { }
}
