// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The reward when a user action performs a liquidation
 * @custom:background Given a protocol initialized with default params
 */
contract LiquidationRewardsUserActions is UsdnProtocolBaseFixture {
    uint128 initialPrice;
    uint128 desiredLiqPrice;
    uint256 balanceSenderBefore;
    uint256 balanceProtocolBefore;
    uint256 liquidationPrice;
    uint256 expectedLiquidatorRewards;
    uint128 depositAmount = 1 ether;
    bytes initialPriceData;
    bytes liquidationPriceData;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = false;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(address(this), 1 ether, address(protocol), 1 ether);
        usdn.approve(address(protocol), type(uint256).max);

        chainlinkGasPriceFeed.setLatestRoundData(1, 30 gwei, block.timestamp, 1);
        vm.txGasPrice(30 gwei);
        initialPrice = params.initialPrice;
        initialPriceData = abi.encode(initialPrice);
        desiredLiqPrice = uint128(initialPrice) * 9 / 10;
        (int24 tick,,) = setUpUserPositionInLong(
            USER_1, ProtocolAction.ValidateOpenPosition, 0.1 ether, desiredLiqPrice, initialPrice
        );

        skip(1 hours);
        balanceSenderBefore = wstETH.balanceOf(address(this));
        balanceProtocolBefore = wstETH.balanceOf(address(protocol));
        liquidationPrice = protocol.getEffectivePriceForTick(tick);
        liquidationPriceData = abi.encode(liquidationPrice);
        expectedLiquidatorRewards = liquidationRewardsManager.getLiquidationRewards(1, 0, false);
        assertGt(expectedLiquidatorRewards, 0, "The expected liquidation rewards should be greater than 0");
    }

    function test_liquidationRewards_initiateDeposit() public {
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateDeposit(depositAmount, liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    function test_liquidationRewards_validateDeposit() public {
        protocol.initiateDeposit(depositAmount, initialPriceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.validateDeposit(liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    function test_liquidationRewards_initiateWithdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, initialPrice);

        skip(1 hours);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateWithdrawal(1 ether, liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }

    function test_liquidationRewards_validateWithdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, 1 ether, initialPrice);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.validateWithdrawal(liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));
        // TODO view function to have the amount of wsETH to be withdrawn (remove +/- 1)
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards + 1, "sender balance");
        assertEq(
            balanceProtocolAfter,
            balanceProtocolBefore + depositAmount - expectedLiquidatorRewards - 1,
            "protocol balance"
        );
    }

    function test_liquidationRewards_initiateOpenPosition() public {
        skip(1 hours);

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.initiateOpenPosition(depositAmount, initialPrice / 2, liquidationPriceData, EMPTY_PREVIOUS_DATA);

        uint256 balanceSenderAfter = wstETH.balanceOf(address(this));
        uint256 balanceProtocolAfter = wstETH.balanceOf(address(protocol));
        assertEq(balanceSenderAfter, balanceSenderBefore + expectedLiquidatorRewards - depositAmount, "sender balance");
        assertEq(
            balanceProtocolAfter, balanceProtocolBefore + depositAmount - expectedLiquidatorRewards, "protocol balance"
        );
    }
}
