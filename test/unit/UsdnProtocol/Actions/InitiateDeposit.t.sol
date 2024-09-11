// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolVaultLibrary as Vault } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/**
 * @custom:feature The initiateDeposit function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsInitiateDeposit is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant POSITION_AMOUNT = 1 ether;
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
        uint128 amountAfterFees =
            uint128(depositAmount - uint256(depositAmount) * protocol.getVaultFeeBps() / BPS_DIVISOR);
        uint128 price = 2000 ether;
        bytes memory currentPrice = abi.encode(price); // only used to apply PnL + funding
        uint256 usdnSharesToMint =
            Vault._calcMintUsdnShares(amountAfterFees, protocol.getBalanceVault(), protocol.getUsdn().totalShares());
        uint256 expectedSdexBurnAmount =
            protocol.i_calcSdexToBurn(usdn.convertToTokens(usdnSharesToMint), protocol.getSdexBurnOnDepositRatio());
        uint256 sdexBalanceBefore = sdex.balanceOf(address(this));
        address deadAddress = protocol.DEAD_ADDRESS();

        vm.expectEmit(address(sdex));
        emit Transfer(address(this), deadAddress, expectedSdexBurnAmount); // SDEX transfer
        vm.expectEmit();
        emit InitiatedDeposit(
            to, validator, depositAmount, protocol.getVaultFeeBps(), block.timestamp, expectedSdexBurnAmount
        );
        bool success = protocol.initiateDeposit(
            depositAmount, DISABLESHARESOUTMIN, to, payable(validator), NO_PERMIT2, currentPrice, EMPTY_PREVIOUS_DATA
        );
        assertTrue(success, "success");

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
        _waitBeforeActionablePendingAction();
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
            1 ether,
            DISABLESHARESOUTMIN,
            address(0),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(uint128(2000 ether)),
            EMPTY_PREVIOUS_DATA
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
            1 ether,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(0)),
            NO_PERMIT2,
            abi.encode(uint128(2000 ether)),
            EMPTY_PREVIOUS_DATA
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
        protocol.initiateDeposit(
            0, DISABLESHARESOUTMIN, address(this), payable(address(this)), NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario The user initiates a small deposit and no USDN would be minted
     * @custom:given The price of wstETH is $0.1
     * @custom:when The user initiates a deposit of 4 wei of wstETH
     * @custom:then The protocol reverts with `UsdnProtocolDepositTooSmall`
     */
    function test_RevertWhen_depositTooSmallNoUSDN() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = 0.1 ether;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);

        uint128 deposited = 4;

        uint256 usdnSharesToMintEstimated =
            Vault._calcMintUsdnShares(deposited, protocol.getBalanceVault(), usdn.totalShares());
        assertEq(usdn.convertToTokens(usdnSharesToMintEstimated), 0, "usdn minted");

        vm.expectRevert(UsdnProtocolDepositTooSmall.selector);
        protocol.initiateDeposit(
            deposited,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
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

        uint256 usdnSharesToMintEstimated =
            Vault._calcMintUsdnShares(deposited, protocol.getBalanceVault(), usdn.totalShares());
        assertGt(usdnSharesToMintEstimated, 0, "usdn minted");

        protocol.initiateDeposit(
            deposited,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(params.initialPrice),
            EMPTY_PREVIOUS_DATA
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
            1 ether,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            currentPrice,
            EMPTY_PREVIOUS_DATA
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
            protocol.initiateDeposit(
                1 ether,
                DISABLESHARESOUTMIN,
                address(this),
                payable(address(this)),
                NO_PERMIT2,
                currentPrice,
                EMPTY_PREVIOUS_DATA
            );
            return;
        }

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.initiateDeposit.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.initiateDeposit{ value: 1 }(
            1 ether,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario A initiate deposit liquidates a tick but is not initiated because another tick still needs to
     * be liquidated
     * @custom:given Two long positions in different ticks
     * @custom:when A user calls `initiateDeposit` with a price below both liquidation prices
     * @custom:then One of the two long positions is liquidated
     * @custom:and The deposit action isn't initiated due to a pending liquidation
     * @custom:and The user wsteth balance should not change
     */
    function test_initiateDepositIsPendingLiquidation() public {
        PositionId memory userPosId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice - params.initialPrice / 5,
                price: params.initialPrice
            })
        );

        _waitMockMiddlewarePriceDelay();

        uint256 wstethBalanceBefore = wstETH.balanceOf(address(this));

        bool success = protocol.initiateDeposit(
            POSITION_AMOUNT,
            DISABLESHARESOUTMIN,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(params.initialPrice / 10),
            EMPTY_PREVIOUS_DATA
        );
        assertFalse(success, "success");

        PendingAction memory pending = protocol.getUserPendingAction(address(this));
        assertEq(uint256(pending.action), uint256(ProtocolAction.None), "user 0 deposit should not be initiated");

        assertEq(
            userPosId.tickVersion + 1, protocol.getTickVersion(userPosId.tick), "user 1 position should be liquidated"
        );

        assertEq(wstethBalanceBefore, wstETH.balanceOf(address(this)), "user 1 should not have spent wstETH");
    }

    /**
     * @custom:scenario The user initiates a deposit action with a predicted mint of USDN shares lower than the
     * parameter
     * @custom:given The user has 1 wstETH
     * @custom:when The user initiates a deposit with 1 wstETH and wants to receive max USDN
     * @custom:then The protocol reverts with `UsdnProtocolAmountReceivedTooSmall`
     */
    function test_RevertWhen_initiateDepositWithEnoughExpectedAmountOut() public {
        vm.expectRevert(UsdnProtocolAmountReceivedTooSmall.selector);
        protocol.initiateDeposit(
            1 ether,
            type(uint256).max,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(uint128(2000 ether)),
            EMPTY_PREVIOUS_DATA
        );
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
