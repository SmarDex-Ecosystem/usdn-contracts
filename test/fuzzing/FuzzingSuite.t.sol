// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { ADMIN, USER_1, USER_2, USER_3, USER_4 } from "../utils/Constants.sol";
import { IUsdnProtocolHandler } from "../utils/IUsdnProtocolHandler.sol";
import { Sdex } from "../utils/Sdex.sol";
import { WstETH } from "../utils/WstEth.sol";
import { FuzzingSuite } from "./FuzzingSuite.sol";

import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";

contract FuzzingSuiteTest is Test {
    FuzzingSuite public fuzzingSuite;
    IUsdnProtocolHandler public usdnProtocol;
    Rebalancer public rebalancer;
    MockOracleMiddleware public wstEthOracleMiddleware;
    WstETH public wsteth;
    Usdn public usdn;

    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });
    uint152 internal usdnShares = 100_000 ether;

    function setUp() public {
        fuzzingSuite = new FuzzingSuite();
        usdnProtocol = fuzzingSuite.usdnProtocol();
        wstEthOracleMiddleware = fuzzingSuite.wstEthOracleMiddleware();
        wsteth = fuzzingSuite.wsteth();
        usdn = fuzzingSuite.usdn();
        rebalancer = fuzzingSuite.rebalancer();
        uint256 usdnBalanceBeforeInit = usdn.balanceOf(USER_1);
        uint128 DEPOSIT_AMOUNT = 300 ether;
        uint128 LONG_AMOUNT = 300 ether;
        uint256 PRICE = 2000 ether;
        uint128 LIQUIDATION_PRICE = 1000 ether;

        vm.prank(USER_1);
        fuzzingSuite.initializeUsdnProtocol(DEPOSIT_AMOUNT, LONG_AMOUNT, PRICE, LIQUIDATION_PRICE);
        assertEq(address(usdnProtocol).balance, 0, "protocol balance");
        assertEq(
            usdn.balanceOf(USER_1), usdnBalanceBeforeInit + (DEPOSIT_AMOUNT * PRICE) / 10 ** 18 - 1000, "usdn balance"
        );
        assertEq(wsteth.balanceOf(address(usdnProtocol)), DEPOSIT_AMOUNT + LONG_AMOUNT, "wstETH balance");

        vm.prank(address(usdnProtocol));
        usdn.mintShares(USER_1, usdnShares);
    }

    function test_canInitiateDeposit() public {
        vm.prank(USER_1);
        fuzzingSuite.initiateDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 1000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateDeposit, "action type");
        assertEq(action.to, USER_1, "action to");
        assertEq(action.validator, USER_1, "action validator");
        assertEq(action.var2, 0.1 ether, "action amount");
    }

    function test_canInitiateOpenPosition() public {
        vm.prank(USER_1);
        fuzzingSuite.initiateOpenPosition(5 ether, 1000 ether, 10 ether, 0, 0, 2000 ether);
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition, "action type");
        assertEq(action.to, USER_1, "action to");
        assertEq(action.validator, USER_1, "action validator");
    }

    function test_canInitiateWithdrawal() public {
        vm.prank(USER_1);
        fuzzingSuite.initiateWithdrawal(usdnShares, 10 ether, 0, 0, 1000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.to, USER_1, "action to");
        assertEq(action.validator, USER_1, "action validator");
        assertEq(action.var1, int24(Vault._calcWithdrawalAmountLSB(usdnShares)), "action amount LSB");
        assertEq(action.var2, Vault._calcWithdrawalAmountMSB(usdnShares), "action amount MSB");
    }

    function test_canValidateDeposit() public {
        Sdex sdex = fuzzingSuite.sdex();
        uint128 amountWstETH = 0.1 ether;
        uint256 price = 1000 ether;

        wsteth.mintAndApprove(USER_1, amountWstETH, address(usdnProtocol), amountWstETH);
        sdex.mintAndApprove(USER_1, 10 ether, address(usdnProtocol), 10 ether);

        uint256 balanceUser1 = usdn.balanceOf(USER_1);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        vm.deal(USER_1, securityDeposit);

        Permit2TokenBitfield.Bitfield NO_PERMIT2 = fuzzingSuite.NO_PERMIT2();

        vm.prank(USER_1);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETH,
            USER_1,
            payable(USER_1),
            NO_PERMIT2,
            abi.encode(price),
            IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) })
        );

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(USER_1);
        fuzzingSuite.validateDeposit(0, price);

        assertGt(usdn.balanceOf(USER_1), balanceUser1, "balance usdn");
    }

    function test_canInitiateDepositAndValidateOpen() public {
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.deal(USER_1, 10 ether);

        vm.prank(USER_1);
        usdn.approve(address(usdnProtocol), usdnShares);
        bytes memory priceData = abi.encode(4000 ether);

        vm.prank(USER_1);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares, USER_3, payable(USER_3), priceData, EMPTY_PREVIOUS_DATA
        );

        skip(usdnProtocol.getValidationDeadline() + 1);
        vm.prank(USER_1);
        fuzzingSuite.initiateDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 4000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateDeposit, "action type");
        assertEq(action.to, USER_1, "action to");
        assertEq(action.validator, USER_1, "action validator");
        assertEq(action.var2, 0.1 ether, "action amount");
    }

    function test_canValidateOpenPosition() public {
        uint128 wstethOpenPositionAmount = 5 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 etherPrice = 4000 ether;
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.deal(USER_1, 10 ether);

        deal(address(wsteth), address(USER_1), wstethOpenPositionAmount);

        vm.startPrank(USER_1);
        wsteth.approve(address(usdnProtocol), wstethOpenPositionAmount);
        usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            wstethOpenPositionAmount,
            liquidationPrice,
            USER_1,
            payable(USER_1),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = USER_1.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(USER_1);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        fuzzingSuite.validateOpenPosition(0, etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(USER_1.balance, balanceBefore + securityDeposit, "USER_1 balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
        assertEq(wsteth.balanceOf(USER_1), balanceWstEthBefore, "wstETH balance");
    }

    function test_canValidateOpenAndPendingActions() public {
        uint128 wstethOpenPositionAmount = 5 ether;
        Sdex sdex = fuzzingSuite.sdex();
        uint128 amountWstETH = 0.1 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 etherPrice = 4000 ether;
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        wsteth.mintAndApprove(
            USER_1,
            amountWstETH + wstethOpenPositionAmount,
            address(usdnProtocol),
            amountWstETH + wstethOpenPositionAmount
        );
        sdex.mintAndApprove(USER_1, 10 ether, address(usdnProtocol), 10 ether);

        vm.deal(USER_1, 10 ether);

        vm.startPrank(USER_1);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETH / 2,
            USER_3,
            payable(USER_3),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETH / 2,
            USER_4,
            payable(USER_4),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            wstethOpenPositionAmount,
            liquidationPrice,
            USER_1,
            payable(USER_1),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = USER_1.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(USER_1);

        skip(usdnProtocol.getValidationDeadline() + 1);
        vm.prank(USER_1);
        fuzzingSuite.validateOpenPosition(0, etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(USER_1.balance, balanceBefore + securityDeposit * 2, "USER_1 balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit * 2, "protocol balance");
        assertEq(wsteth.balanceOf(USER_1), balanceWstEthBefore, "wstETH balance");
    }

    function test_canValidateWithdrawal() public {
        vm.deal(USER_1, 10 ether);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        vm.prank(USER_1);
        usdn.approve(address(usdnProtocol), usdnShares);
        bytes memory priceData = abi.encode(4000 ether);

        vm.prank(USER_1);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares, USER_1, payable(USER_1), priceData, EMPTY_PREVIOUS_DATA
        );

        uint256 balanceBefore = USER_1.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(USER_1);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(USER_1);
        fuzzingSuite.validateWithdrawal(0, 4000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(USER_1.balance, balanceBefore + securityDeposit, "USER_1 balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
        assertGt(wsteth.balanceOf(USER_1), balanceWstEthBefore, "wstETH balance");
    }

    function test_canValidateClose() public {
        uint128 wstethOpenPositionAmount = 5 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 etherPrice = 4000 ether;
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(etherPrice);
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;

        vm.deal(USER_1, 10 ether);
        deal(address(wsteth), address(USER_1), wstethOpenPositionAmount);
        wsteth.mintAndApprove(USER_1, wstethOpenPositionAmount, address(usdnProtocol), wstethOpenPositionAmount);

        vm.startPrank(USER_1);
        _validateCloseAndAssert(
            securityDeposit, wstethOpenPositionAmount, liquidationPrice, etherPrice, priceData, rawIndices
        );
    }

    function test_canValidateCloseAndPendingAction() public {
        uint128 amountWstETHPending = 0.1 ether;
        uint128 wstethOpenPositionAmount = 5 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 etherPrice = 4000 ether;
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        bytes[] memory priceData = new bytes[](1);
        priceData[0] = abi.encode(etherPrice);
        uint128[] memory rawIndices = new uint128[](1);
        rawIndices[0] = 0;
        Sdex sdex = fuzzingSuite.sdex();

        vm.deal(USER_1, 10 ether);
        wsteth.mintAndApprove(
            USER_1,
            amountWstETHPending + wstethOpenPositionAmount,
            address(usdnProtocol),
            amountWstETHPending + wstethOpenPositionAmount
        );
        sdex.mintAndApprove(USER_1, 10 ether, address(usdnProtocol), 10 ether);

        vm.startPrank(USER_1);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETHPending / 2,
            USER_3,
            payable(USER_3),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETHPending / 2,
            USER_4,
            payable(USER_4),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        _validateCloseAndAssert(
            securityDeposit, wstethOpenPositionAmount, liquidationPrice, etherPrice, priceData, rawIndices
        );
    }

    function test_canValidatePendingActions() public {
        vm.deal(USER_1, 10 ether);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        bytes memory priceData = abi.encode(4000 ether);

        vm.startPrank(USER_1);
        usdn.approve(address(usdnProtocol), usdnShares);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares / 2, USER_3, payable(USER_3), priceData, EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares / 2, USER_4, payable(USER_4), priceData, EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = USER_1.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;

        skip(usdnProtocol.getValidationDeadline() + 1);

        vm.prank(USER_1);
        fuzzingSuite.validatePendingActions(10, 4000 ether);

        assertEq(USER_1.balance, balanceBefore + securityDeposit * 2, "USER_1 balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit * 2, "protocol balance");
    }

    function test_canInitiateClosePosition() public {
        test_canFullOpenPosition();
        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.prank(USER_1);
        fuzzingSuite.initiateClosePosition(securityDeposit, 0, 0, 4000 ether, 1 ether, 0);

        assertEq(
            uint8(usdnProtocol.getUserPendingAction(USER_1).action),
            uint8(IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition),
            "The user action should pending"
        );
    }

    function test_canFullDeposit() public {
        uint256 balanceUser1 = usdn.balanceOf(USER_1);
        uint256 balanceProtocol = address(usdnProtocol).balance;

        vm.prank(USER_1);
        fuzzingSuite.fullDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 1000 ether);

        assertGt(usdn.balanceOf(USER_1), balanceUser1, "balance usdn");
        assertEq(address(usdnProtocol).balance, balanceProtocol, "protocol balance");
    }

    function test_canFullWithdrawal() public {
        assertGt(usdn.balanceOf(USER_1), 0, "usdn balance before withdrawal");
        uint256 balanceProtocol = address(usdnProtocol).balance;
        uint256 usdnSharesBefore = usdn.sharesOf(USER_1);

        vm.prank(USER_1);
        fuzzingSuite.fullWithdrawal(usdnShares, 10 ether, 0, 0, 1000 ether);

        assertEq(usdn.sharesOf(USER_1), usdnSharesBefore - usdnShares, "usdn shares balance after withdrawal");
        assertEq(address(usdnProtocol).balance, balanceProtocol, "protocol balance");
    }

    function test_canFullOpenPosition() public {
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(USER_1);

        vm.prank(USER_1);
        fuzzingSuite.fullOpenPosition(5 ether, 1000 ether, 10 ether, 0, 0, 2000 ether);

        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol, "protocol balance");
        assertEq(wsteth.balanceOf(USER_1), balanceWstEthBefore, "wstETH balance");
    }

    function test_canFullClosePosition() public {
        test_canFullOpenPosition();
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);

        assertEq(
            uint8(usdnProtocol.getUserPendingAction(USER_1).action),
            uint8(IUsdnProtocolTypes.ProtocolAction.None),
            "The user action should be none"
        );
        uint256 balanceBeforeWsteth = wsteth.balanceOf(USER_1);

        vm.prank(USER_1);
        fuzzingSuite.fullClosePosition(securityDeposit, 0, 0, 2000 ether, 5 ether, 0);

        // the protocol fees are collected during all skip. So, wee have a delta of 1.05e15(0.105%)
        assertApproxEqRel(wsteth.balanceOf(USER_1), balanceBeforeWsteth + 5 ether, 1.05e15, "wstETH balance");
        assertEq(
            uint8(usdnProtocol.getUserPendingAction(USER_1).action),
            uint8(IUsdnProtocolTypes.ProtocolAction.None),
            "The user action should be none"
        );
    }

    function test_canTransfer() public {
        uint256 amount = 10 ether;
        vm.deal(USER_1, amount);
        vm.prank(address(usdnProtocol));
        usdn.mintShares(USER_1, amount);
        wsteth.mintAndApprove(USER_1, amount, address(this), amount);
        uint256 balanceBefore = USER_1.balance;
        uint256 balanceBeforeProtocol = USER_2.balance;
        uint256 balanceBeforeWstEth = wsteth.balanceOf(USER_1);
        uint256 sharesBeforeUsdn = usdn.sharesOf(USER_1);

        vm.prank(USER_1);
        fuzzingSuite.transfer(0, amount, 0);
        vm.prank(USER_1);
        fuzzingSuite.transfer(1, amount, 0);
        vm.prank(USER_1);
        fuzzingSuite.transfer(2, amount, 0);
        assertEq(USER_1.balance, balanceBefore - amount, "USER_1 balance");
        assertEq(usdn.sharesOf(USER_1), sharesBeforeUsdn - amount, "USER_1 usdn shares");
        assertEq(wsteth.balanceOf(USER_1), balanceBeforeWstEth - amount, "USER_1 wsteth balance");
        assertEq(USER_2.balance, balanceBeforeProtocol + amount, "protocol balance");
        assertEq(usdn.sharesOf(USER_2), amount, "protocol usdn shares");
        assertEq(wsteth.balanceOf(USER_2), amount, "protocol wsteth balance");
    }

    function test_canLiquidate() public {
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        uint128 currentPrice = 2000 ether;
        bytes memory priceData = abi.encode(currentPrice);
        wsteth.mintAndApprove(USER_1, 1_000_000 ether, address(usdnProtocol), type(uint256).max);
        vm.deal(USER_1, 1_000_000 ether);

        vm.prank(ADMIN);
        usdnProtocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);
        vm.startPrank(USER_1);
        // create high risk position (10% of the liquidation price)
        usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            5 ether,
            9 * currentPrice / 10,
            USER_1,
            payable(USER_1),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(currentPrice),
            EMPTY_PREVIOUS_DATA
        );

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        usdnProtocol.validateOpenPosition(payable(USER_1), abi.encode(currentPrice), EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        // price drops under a valid liquidation price
        uint256 priceDecrease = 1700 ether;
        priceData = abi.encode(priceDecrease);

        // liquidate
        uint256 balanceBefore = address(this).balance;
        uint256 validationCost =
            wstEthOracleMiddleware.validationCost(priceData, IUsdnProtocolTypes.ProtocolAction.Liquidation);
        uint256 initialTotalPos = usdnProtocol.getTotalLongPositions();

        skip(30 seconds);
        vm.prank(USER_1);
        fuzzingSuite.liquidate(priceDecrease, 10, validationCost);
        assertEq(usdnProtocol.getTotalLongPositions(), initialTotalPos - 1, "total positions after liquidate");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    function _validateCloseAndAssert(
        uint256 securityDeposit,
        uint128 wstethOpenPositionAmount,
        uint128 liquidationPrice,
        uint256 etherPrice,
        bytes[] memory priceData,
        uint128[] memory rawIndices
    ) internal {
        (, IUsdnProtocolTypes.PositionId memory posId) = usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            wstethOpenPositionAmount,
            liquidationPrice,
            USER_1,
            payable(USER_1),
            fuzzingSuite.NO_PERMIT2(),
            abi.encode(etherPrice),
            IUsdnProtocolTypes.PreviousActionsData(priceData, rawIndices)
        );
        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        usdnProtocol.validateOpenPosition(payable(USER_1), abi.encode(etherPrice), EMPTY_PREVIOUS_DATA);
        usdnProtocol.initiateClosePosition{ value: securityDeposit }(
            posId, wstethOpenPositionAmount, USER_1, payable(USER_1), abi.encode(etherPrice), EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = USER_1.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(USER_1);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(USER_1);
        fuzzingSuite.validateClosePosition(0, etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(USER_1);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(USER_1.balance, balanceBefore + securityDeposit, "USER_1 balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
        assertGt(wsteth.balanceOf(USER_1), balanceWstEthBefore, "wstETH balance");
        assertLt(wsteth.balanceOf(USER_1), balanceWstEthBefore + wstethOpenPositionAmount, "wstETH balance");
    }

    function test_adminFunctions() public {
        fuzzingSuite.setMinLeverage(10 ** 21 * 2);
        assertEq(usdnProtocol.getMinLeverage(), 10 ** 21 * 2, "minLeverage");

        fuzzingSuite.setMaxLeverage(10 ** 21 * 9);
        assertEq(usdnProtocol.getMaxLeverage(), 10 ** 21 * 9, "maxLeverage");

        fuzzingSuite.setValidationDeadline(0.5 days);
        assertEq(usdnProtocol.getValidationDeadline(), 0.5 days, "validationDeadline");

        fuzzingSuite.setLiquidationPenalty(10);
        assertEq(usdnProtocol.getLiquidationPenalty(), 10, "liquidationPenalty");

        fuzzingSuite.setSafetyMarginBps(10);
        assertEq(usdnProtocol.getSafetyMarginBps(), 10, "safetyMarginBps");

        fuzzingSuite.setLiquidationIteration(8);
        assertEq(usdnProtocol.getLiquidationIteration(), 8, "liquidationIteration");

        fuzzingSuite.setEMAPeriod(1 days);
        assertEq(usdnProtocol.getEMAPeriod(), 1 days, "emaPeriod");

        fuzzingSuite.setFundingSF(500);
        assertEq(usdnProtocol.getFundingSF(), 500, "fundingSF");

        fuzzingSuite.setProtocolFeeBps(5000);
        assertEq(usdnProtocol.getProtocolFeeBps(), 5000, "protocolFeeBps");

        fuzzingSuite.setPositionFeeBps(1000);
        assertEq(usdnProtocol.getPositionFeeBps(), 1000, "positionFeeBps");

        fuzzingSuite.setVaultFeeBps(1000);
        assertEq(usdnProtocol.getVaultFeeBps(), 1000, "vaultFeeBps");

        fuzzingSuite.setRebalancerBonusBps(1000);
        assertEq(usdnProtocol.getRebalancerBonusBps(), 1000, "rebalancerBonusBps");

        fuzzingSuite.setSdexBurnOnDepositRatio(1e4);
        assertEq(usdnProtocol.getSdexBurnOnDepositRatio(), 1e4, "sdexBurnOnDepositRatio");

        fuzzingSuite.setSecurityDepositValue(1e19);
        assertEq(usdnProtocol.getSecurityDepositValue(), 1e19, "securityDepositValue");

        fuzzingSuite.setFeeThreshold(1e30);
        assertEq(usdnProtocol.getFeeThreshold(), 1e30, "feeThreshold");

        fuzzingSuite.setFeeCollector(USER_1);
        assertEq(usdnProtocol.getFeeCollector(), USER_1, "feeCollector");

        fuzzingSuite.setExpoImbalanceLimits(5000, 0, 10_000, 1, -4900);
        assertEq(usdnProtocol.getOpenExpoImbalanceLimitBps(), 5000, "openExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getDepositExpoImbalanceLimitBps(), 1, "depositExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getWithdrawalExpoImbalanceLimitBps(), 10_000, "withdrawalExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getCloseExpoImbalanceLimitBps(), 1, "closeExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getLongImbalanceTargetBps(), -4900, "longImbalanceTargetBps");

        fuzzingSuite.setTargetUsdnPrice(1e18);
        assertEq(usdnProtocol.getTargetUsdnPrice(), 1e18, "targetUsdnPrice");

        fuzzingSuite.setUsdnRebaseThreshold(1e30);
        assertEq(usdnProtocol.getUsdnRebaseThreshold(), 1e30, "usdnRebaseThreshold");

        fuzzingSuite.setUsdnRebaseInterval(1e20);
        assertEq(usdnProtocol.getUsdnRebaseInterval(), 1e20, "usdnRebaseInterval");

        fuzzingSuite.setMinLongPosition(1e24);
        assertEq(usdnProtocol.getMinLongPosition(), 1e24, "minLongPosition");
    }

    function test_canInitiateDepositRebalancer() public {
        uint256 wstethDepositAmount = 5 ether;
        uint256 balanceWstethBefore = wsteth.balanceOf(USER_1);

        vm.prank(USER_1);
        fuzzingSuite.initiateDepositRebalancer(wstethDepositAmount, 0);

        assertEq(wsteth.balanceOf(USER_1), balanceWstethBefore, "deployer wsteth balance");
        assertEq(wsteth.balanceOf(address(rebalancer)), wstethDepositAmount, "rebalancer wsteth balance");
    }
}
