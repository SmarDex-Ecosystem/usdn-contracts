// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

import {
    PendingAction,
    ProtocolAction,
    Position,
    PositionId,
    DepositPendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiateDeposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsInitiateDeposit is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant POSITION_AMOUNT = 1 ether;
    uint256 internal securityDeposit;
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

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
        _initiateDepositScenario(address(this), address(this));
    }

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH with another user as the beneficiary
     * @custom:given The to parameter is different from the sender of the transaction
     * @custom:when initiateDeposit function is called
     * @custom:then The protocol emits an `InitiatedDeposit` event with the right beneficiary
     * @custom:and The user has a pending action of type `InitiateDeposit` with the right beneficiary
     */
    function test_initiateDepositForAnotherUser() public {
        _initiateDepositScenario(USER_1, USER_1);
    }

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH with another validator
     * @custom:given The validator parameter is different from the sender of the transaction
     * @custom:when initiateDeposit function is called
     * @custom:then The protocol emits an `InitiatedDeposit` event with the right validator
     * @custom:and The user has a pending action of type `InitiateDeposit` with the right validator
     */
    function test_initiateDepositDifferentValidator() public {
        _initiateDepositScenario(address(this), USER_1);
    }

    function _initiateDepositScenario(address to, address validator) internal {
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
        emit InitiatedDeposit(to, validator, depositAmount, block.timestamp);
        protocol.initiateDeposit(depositAmount, to, validator, currentPrice, EMPTY_PREVIOUS_DATA);

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

        PendingAction memory action = protocol.getUserPendingAction(validator);
        assertTrue(action.action == ProtocolAction.ValidateDeposit, "action type");
        assertEq(action.timestamp, block.timestamp, "action timestamp");
        assertEq(action.to, to, "action to");
        assertEq(action.validator, validator, "action validator");
        assertEq(action.var2, depositAmount, "action amount");

        // the pending action should be actionable after the validation deadline
        skip(protocol.getValidationDeadline() + 1);
        (actions,) = protocol.getActionablePendingActions(address(0));
        assertEq(actions[0].to, to, "pending action to");
        assertEq(actions[0].validator, validator, "pending action validator");
    }

    /**
     * @custom:scenario The user initiates a deposit with parameter to defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates a deposit with parameter to defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolInvalidAddressTo`
     */
    function test_RevertWhen_zeroAddressTo() public {
        vm.expectRevert(UsdnProtocolInvalidAddressTo.selector);
        protocol.initiateDeposit(
            1 ether, address(0), address(this), abi.encode(uint128(2000 ether)), EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates a deposit with parameter validator defined at zero
     * @custom:given An initialized USDN protocol
     * @custom:when The user initiates a deposit with parameter validator defined at zero
     * @custom:then The protocol reverts with `UsdnProtocolInvalidAddressValidator`
     */
    function test_RevertWhen_zeroAddressValidator() public {
        vm.expectRevert(UsdnProtocolInvalidAddressValidator.selector);
        protocol.initiateDeposit(
            1 ether, address(this), address(0), abi.encode(uint128(2000 ether)), EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates a deposit of 0 wstETH
     * @custom:when The user initiates a deposit of 0 wstETH
     * @custom:then The protocol reverts with `UsdnProtocolZeroAmount`
     */
    function test_RevertWhen_zeroAmount() public {
        bytes memory priceData = abi.encode(uint128(2000 ether));
        vm.expectRevert(UsdnProtocolZeroAmount.selector);
        protocol.initiateDeposit(0, address(this), address(this), priceData, EMPTY_PREVIOUS_DATA);
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
        protocol.initiateDeposit(
            deposited, address(this), address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
        );
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
        protocol.initiateDeposit(
            deposited, address(this), address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
        );
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

        protocol.initiateDeposit(
            deposited, address(this), address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
        );
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
        protocol.initiateDeposit{ value: 0.5 ether }(
            1 ether, address(this), address(this), currentPrice, EMPTY_PREVIOUS_DATA
        );
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user initiates a deposit action with a reentrancy attempt
     * @custom:given A user being a smart contract that calls initiateDeposit with too much ether
     * @custom:and A receive() function that calls initiateDeposit again
     * @custom:when The user calls initiateDeposit again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_initiateDepositCalledWithReentrancy() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));

        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.initiateDeposit(1 ether, address(this), address(this), currentPrice, EMPTY_PREVIOUS_DATA);
            return;
        }

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateDeposit.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateDeposit{ value: 1 }(1 ether, address(this), address(this), currentPrice, EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario A initiate deposit liquidates a pending tick but is not validated
     * because a tick still needs to be liquidated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drops below all position liquidation prices
     * @custom:when The first `initiateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still needs to be liquidated
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
                POSITION_AMOUNT, address(this), address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
                POSITION_AMOUNT, address(this), address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
     * because a tick still needs to be liquidated. In the same block another deposit
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drops below all position liquidation prices
     * @custom:when The first `initiateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still needs to be liquidated
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
                POSITION_AMOUNT, address(this), address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
                POSITION_AMOUNT, address(this), address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
     * because a tick still needs to be liquidated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and A user initiateDeposit position is pending
     * @custom:and The price drops below all position liquidation prices
     * @custom:when The first `validateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still needs to be liquidated
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
                POSITION_AMOUNT, address(this), address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action was validated");

            _waitDelay();

            protocol.validateDeposit{ value: securityDeposit }(
                address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
                address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
     * because a tick still needs to be liquidated. In the same block another deposit
     * liquid the remaining tick and is validated
     * @custom:given The initial open position
     * @custom:and A user open position
     * @custom:and The price drops below all position liquidation prices
     * @custom:when The first `validateDeposit` is called
     * @custom:and The initial open position tick is liquidated
     * @custom:and The user open position tick still needs to be liquidated
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
                POSITION_AMOUNT, address(this), address(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.ValidateDeposit), "user action was validated");

            _waitDelay();

            protocol.validateDeposit{ value: securityDeposit }(
                address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
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
                address(this), abi.encode(params.initialPrice / 10), EMPTY_PREVIOUS_DATA
            );

            PendingAction memory pending = protocol.getUserPendingAction(address(this));
            assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user action was not validated");

            assertEq(
                userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user position is not liquidated"
            );

            assertLt(usdnBalanceBefore, usdn.balanceOf(address(this)), "user usdn balance is lower or equal");
        }
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_initiateDepositCalledWithReentrancy();
            _reenter = false;
        }
    }
}
