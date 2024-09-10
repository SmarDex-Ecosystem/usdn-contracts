// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm } from "forge-std/Vm.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The reward when a user action performs a liquidation during an action
 * @custom:background Given a protocol initialized with default params with a user position with a liquidation price at
 * 90% of the initial price
 */
contract TestLiquidationRewardsUserActions is UsdnProtocolBaseFixture {
    bytes initialPriceData;
    bytes liquidationPriceData;

    uint128 initialPrice;
    uint128 liquidationPrice;
    uint128 depositAmount = 1 ether;

    uint256 balanceSenderBefore;
    uint256 balanceProtocolBefore;
    uint256 expectedLiquidatorRewards;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 1 ether, address(protocol), 1 ether);
        usdn.approve(address(protocol), type(uint256).max);

        chainlinkGasPriceFeed.setLatestRoundData(1, 30 gwei, block.timestamp, 1);
        vm.txGasPrice(30 gwei);

        initialPrice = params.initialPrice;
        uint128 desiredLiqPrice = uint128(initialPrice) * 9 / 10;
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 0.1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: initialPrice
            })
        );
        skip(1 hours);

        balanceSenderBefore = wstETH.balanceOf(address(this));
        balanceProtocolBefore = wstETH.balanceOf(address(protocol));
        liquidationPrice = protocol.getEffectivePriceForTick(posId.tick);
        liquidationPriceData = abi.encode(liquidationPrice);
        initialPriceData = abi.encode(initialPrice);
        expectedLiquidatorRewards = liquidationRewardsManager.getLiquidationRewards(
            1, 0, false, Types.TriggerRebalancerChecks.None, ProtocolAction.None, "", ""
        );

        assertGt(expectedLiquidatorRewards, 0, "The expected liquidation rewards should be greater than 0");
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an initiate deposit action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `initiateDeposit` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_initiateDeposit() public {
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateDeposit(
            depositAmount, address(this), payable(address(this)), NO_PERMIT2, liquidationPriceData, EMPTY_PREVIOUS_DATA
        );

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            balanceSenderBefore + balanceProtocolBefore, balanceSenderAfter + balanceProtocolAfter, "total balance"
        );
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an validate deposit action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `validateDeposit` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_validateDeposit() public {
        protocol.initiateDeposit(
            depositAmount, address(this), payable(address(this)), NO_PERMIT2, initialPriceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.validateDeposit(payable(address(this)), liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            balanceSenderBefore + balanceProtocolBefore, balanceSenderAfter + balanceProtocolAfter, "total balance"
        );
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an initiate withdrawal action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `initiateWithdrawal` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_initiateWithdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, depositAmount, initialPrice);

        skip(1 hours);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateWithdrawal(
            uint152(usdn.balanceOf(address(this))),
            address(this),
            payable(address(this)),
            liquidationPriceData,
            EMPTY_PREVIOUS_DATA
        );

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            // we have to add the deposit amount of the new position
            balanceSenderBefore + balanceProtocolBefore + depositAmount,
            balanceSenderAfter + balanceProtocolAfter,
            "total balance"
        );
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an validate withdrawal action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `validateWithdrawal` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_validateWithdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, depositAmount, initialPrice);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        vm.recordLogs();
        protocol.validateWithdrawal(payable(address(this)), liquidationPriceData, EMPTY_PREVIOUS_DATA);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 amountWithdrawn;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IUsdnProtocolEvents.ValidatedWithdrawal.selector) {
                (amountWithdrawn,,) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            }
        }
        assertGt(amountWithdrawn, 0, "withdrawn amount");

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            // we have to add the deposit amount of the new position
            balanceSenderBefore + balanceProtocolBefore + depositAmount,
            balanceSenderAfter + balanceProtocolAfter,
            "total balance"
        );
        assertEq(
            balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards + amountWithdrawn, "sender balance"
        );
        assertEq(
            balanceProtocolAfter,
            balanceProtocolBefore - expectedLiquidatorRewards + depositAmount - amountWithdrawn,
            "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an initiate open position
     * action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `initiateOpenPosition` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_initiateOpenPosition() public {
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateOpenPosition(
            depositAmount,
            initialPrice / 2,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            liquidationPriceData,
            EMPTY_PREVIOUS_DATA
        );

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            balanceSenderBefore + balanceProtocolBefore, balanceSenderAfter + balanceProtocolAfter, "total balance"
        );
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an validate open position
     * action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `validateOpenPosition` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_validateOpenPosition() public {
        protocol.initiateOpenPosition(
            depositAmount,
            initialPrice / 2,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            initialPriceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.validateOpenPosition(payable(address(this)), liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            balanceSenderBefore + balanceProtocolBefore, balanceSenderAfter + balanceProtocolAfter, "total balance"
        );
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an initiate close position
     * action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `initiateClosePosition` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_initiateClosePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: depositAmount,
                desiredLiqPrice: initialPrice / 2,
                price: initialPrice
            })
        );

        skip(1 hours);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateClosePosition(
            posId, depositAmount, address(this), payable(address(this)), liquidationPriceData, EMPTY_PREVIOUS_DATA
        );

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            // we have to add the deposit amount of the new position
            balanceSenderBefore + balanceProtocolBefore + depositAmount,
            balanceSenderAfter + balanceProtocolAfter,
            "total balance"
        );
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    /**
     * @custom:scenario The sender should receive the liquidation rewards when performing an validate close position
     * action
     * @custom:given A user position at a liquidation price of 90% of the initial price
     * @custom:when The `validateClosePosition` function is called
     * @custom:then The sender should receive the liquidation rewards
     */
    function test_liquidationRewards_validateClosePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: depositAmount,
                desiredLiqPrice: initialPrice / 2,
                price: initialPrice
            })
        );

        skip(1 hours);

        (PendingAction memory action,) = protocol.i_getPendingAction(address(this));
        LongPendingAction memory longAction = protocol.i_toLongPendingAction(action);
        uint256 priceWithFees =
            liquidationPrice - (liquidationPrice * protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();

        int256 positionValue = protocol.i_positionValue(
            uint128(priceWithFees),
            protocol.i_getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick), longAction.liqMultiplier),
            longAction.closePosTotalExpo
        );

        uint256 vaultProfit = depositAmount - uint256(positionValue);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.validateClosePosition(payable(address(this)), liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));

        assertEq(
            // we have to add the deposit amount of the new position
            balanceSenderBefore + balanceProtocolBefore + depositAmount,
            balanceSenderAfter + balanceProtocolAfter,
            "total balance"
        );
        assertEq(
            balanceSenderAfter,
            balanceSenderBefore + expectedLiquidatorRewards + uint256(positionValue),
            "sender balance"
        );
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore - expectedLiquidatorRewards + vaultProfit, "protocol balance"
        );
    }
}
