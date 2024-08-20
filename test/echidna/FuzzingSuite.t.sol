// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { UsdnProtocolHandler } from "../unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { USER_1, USER_2 } from "../utils/Constants.sol";
import { IUsdnProtocolHandler } from "../utils/IUsdnProtocolHandler.sol";
import { Sdex } from "../utils/Sdex.sol";
import { WstETH } from "../utils/WstEth.sol";
import { FuzzingSuite } from "./FuzzingSuite.sol";

import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";

contract FuzzingSuiteTest is Test {
    FuzzingSuite public echidna;
    IUsdnProtocolHandler public usdnProtocol;
    MockOracleMiddleware public wstEthOracleMiddleware;
    WstETH public wsteth;
    Usdn public usdn;

    address internal DEPLOYER;
    address internal ATTACKER;
    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });
    uint152 internal usdnShares = 100_000 ether;

    function setUp() public {
        echidna = new FuzzingSuite();
        DEPLOYER = echidna.DEPLOYER();
        ATTACKER = echidna.ATTACKER();
        usdnProtocol = echidna.usdnProtocol();
        wstEthOracleMiddleware = echidna.wstEthOracleMiddleware();
        wsteth = echidna.wsteth();
        usdn = echidna.usdn();
        uint256 usdnBalanceBeforeInit = usdn.balanceOf(DEPLOYER);
        uint256 DEPOSIT_AMOUNT = 300 ether;
        uint256 LONG_AMOUNT = 300 ether;
        uint256 PRICE = 2000 ether;
        uint256 LIQUIDATION_PRICE = 1000 ether;

        vm.prank(DEPLOYER);
        echidna.initializeUsdnProtocol(DEPOSIT_AMOUNT, LONG_AMOUNT, PRICE, LIQUIDATION_PRICE);
        assertEq(address(usdnProtocol).balance, 0, "protocol balance");
        assertEq(
            usdn.balanceOf(DEPLOYER), usdnBalanceBeforeInit + (DEPOSIT_AMOUNT * PRICE) / 10 ** 18 - 1000, "usdn balance"
        );
        assertEq(wsteth.balanceOf(address(usdnProtocol)), DEPOSIT_AMOUNT + LONG_AMOUNT, "wstETH balance");

        vm.prank(address(usdnProtocol));
        usdn.mintShares(DEPLOYER, usdnShares);
    }

    function test_canInitiateDeposit() public {
        vm.prank(DEPLOYER);
        echidna.initiateDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 1000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateDeposit, "action type");
        assertEq(action.to, DEPLOYER, "action to");
        assertEq(action.validator, DEPLOYER, "action validator");
        assertEq(action.var2, 0.1 ether, "action amount");
    }

    function test_canInitiateOpenPosition() public {
        vm.prank(DEPLOYER);
        echidna.initiateOpenPosition(5 ether, 1000 ether, 10 ether, 0, 0, 2000 ether);
        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition, "action type");
        assertEq(action.to, DEPLOYER, "action to");
        assertEq(action.validator, DEPLOYER, "action validator");
    }

    function test_canInitiateWithdrawal() public {
        vm.prank(DEPLOYER);
        echidna.initiateWithdrawal(usdnShares, 10 ether, 0, 0, 1000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.to, DEPLOYER, "action to");
        assertEq(action.validator, DEPLOYER, "action validator");
        assertEq(action.var1, int24(Vault._calcWithdrawalAmountLSB(usdnShares)), "action amount LSB");
        assertEq(action.var2, Vault._calcWithdrawalAmountMSB(usdnShares), "action amount MSB");
    }

    function test_canValidateDeposit() public {
        Sdex sdex = echidna.sdex();
        uint128 amountWstETH = 0.1 ether;
        uint256 price = 1000 ether;

        wsteth.mintAndApprove(DEPLOYER, amountWstETH, address(usdnProtocol), amountWstETH);
        sdex.mintAndApprove(DEPLOYER, 10 ether, address(usdnProtocol), 10 ether);

        uint256 balanceDeployer = usdn.balanceOf(DEPLOYER);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        vm.deal(DEPLOYER, securityDeposit);

        Permit2TokenBitfield.Bitfield NO_PERMIT2 = echidna.NO_PERMIT2();

        vm.prank(DEPLOYER);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETH,
            DEPLOYER,
            payable(DEPLOYER),
            NO_PERMIT2,
            abi.encode(price),
            IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) })
        );

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(DEPLOYER);
        echidna.validateDeposit(0, price);

        assertGt(usdn.balanceOf(DEPLOYER), balanceDeployer, "balance usdn");
    }

    function test_canInitiateDepositAndValidateOpen() public {
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.deal(DEPLOYER, 10 ether);

        vm.prank(DEPLOYER);
        usdn.approve(address(usdnProtocol), usdnShares);
        bytes memory priceData = abi.encode(4000 ether);

        vm.prank(DEPLOYER);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares, USER_1, payable(USER_1), priceData, EMPTY_PREVIOUS_DATA
        );

        skip(usdnProtocol.getValidationDeadline() + 1);
        vm.prank(DEPLOYER);
        echidna.initiateDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 4000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateDeposit, "action type");
        assertEq(action.to, DEPLOYER, "action to");
        assertEq(action.validator, DEPLOYER, "action validator");
        assertEq(action.var2, 0.1 ether, "action amount");
    }

    function test_canValidateOpenPosition() public {
        uint128 wstethOpenPositionAmount = 5 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 etherPrice = 4000 ether;
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.deal(DEPLOYER, 10 ether);

        deal(address(wsteth), address(DEPLOYER), wstethOpenPositionAmount);

        vm.startPrank(DEPLOYER);
        wsteth.approve(address(usdnProtocol), wstethOpenPositionAmount);
        usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            wstethOpenPositionAmount,
            liquidationPrice,
            DEPLOYER,
            payable(DEPLOYER),
            echidna.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = DEPLOYER.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(DEPLOYER);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        echidna.validateOpenPosition(uint256(uint160(DEPLOYER)), etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(DEPLOYER.balance, balanceBefore + securityDeposit, "DEPLOYER balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
        assertEq(wsteth.balanceOf(DEPLOYER), balanceWstEthBefore, "wstETH balance");
    }

    function test_canValidateOpenAndPendingActions() public {
        uint128 wstethOpenPositionAmount = 5 ether;
        Sdex sdex = echidna.sdex();
        uint128 amountWstETH = 0.1 ether;
        uint128 liquidationPrice = 1000 ether;
        uint256 etherPrice = 4000 ether;
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        wsteth.mintAndApprove(
            DEPLOYER,
            amountWstETH + wstethOpenPositionAmount,
            address(usdnProtocol),
            amountWstETH + wstethOpenPositionAmount
        );
        sdex.mintAndApprove(DEPLOYER, 10 ether, address(usdnProtocol), 10 ether);

        vm.deal(DEPLOYER, 10 ether);

        vm.startPrank(DEPLOYER);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETH / 2, USER_1, payable(USER_1), echidna.NO_PERMIT2(), abi.encode(etherPrice), EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETH / 2, USER_2, payable(USER_2), echidna.NO_PERMIT2(), abi.encode(etherPrice), EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            wstethOpenPositionAmount,
            liquidationPrice,
            DEPLOYER,
            payable(DEPLOYER),
            echidna.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = DEPLOYER.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(DEPLOYER);

        skip(usdnProtocol.getValidationDeadline() + 1);
        vm.prank(DEPLOYER);
        echidna.validateOpenPosition(uint256(uint160(DEPLOYER)), etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(DEPLOYER.balance, balanceBefore + securityDeposit * 2, "DEPLOYER balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit * 2, "protocol balance");
        assertEq(wsteth.balanceOf(DEPLOYER), balanceWstEthBefore, "wstETH balance");
    }

    function test_canValidateWithdrawal() public {
        vm.deal(DEPLOYER, 10 ether);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        vm.prank(DEPLOYER);
        usdn.approve(address(usdnProtocol), usdnShares);
        bytes memory priceData = abi.encode(4000 ether);

        vm.prank(DEPLOYER);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares, DEPLOYER, payable(DEPLOYER), priceData, EMPTY_PREVIOUS_DATA
        );

        uint256 balanceBefore = DEPLOYER.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(DEPLOYER);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(DEPLOYER);
        echidna.validateWithdrawal(0, 4000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(DEPLOYER.balance, balanceBefore + securityDeposit, "DEPLOYER balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
        assertGt(wsteth.balanceOf(DEPLOYER), balanceWstEthBefore, "wstETH balance");
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

        vm.deal(DEPLOYER, 10 ether);
        deal(address(wsteth), address(DEPLOYER), wstethOpenPositionAmount);
        wsteth.mintAndApprove(DEPLOYER, wstethOpenPositionAmount, address(usdnProtocol), wstethOpenPositionAmount);

        vm.startPrank(DEPLOYER);
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
        Sdex sdex = echidna.sdex();

        vm.deal(DEPLOYER, 10 ether);
        wsteth.mintAndApprove(
            DEPLOYER,
            amountWstETHPending + wstethOpenPositionAmount,
            address(usdnProtocol),
            amountWstETHPending + wstethOpenPositionAmount
        );
        sdex.mintAndApprove(DEPLOYER, 10 ether, address(usdnProtocol), 10 ether);

        vm.startPrank(DEPLOYER);
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETHPending / 2,
            USER_1,
            payable(USER_1),
            echidna.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountWstETHPending / 2,
            USER_2,
            payable(USER_2),
            echidna.NO_PERMIT2(),
            abi.encode(etherPrice),
            EMPTY_PREVIOUS_DATA
        );
        _validateCloseAndAssert(
            securityDeposit, wstethOpenPositionAmount, liquidationPrice, etherPrice, priceData, rawIndices
        );
    }

    function test_canValidatePendingActions() public {
        vm.deal(DEPLOYER, 10 ether);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        bytes memory priceData = abi.encode(4000 ether);

        vm.startPrank(DEPLOYER);
        usdn.approve(address(usdnProtocol), usdnShares);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares / 2, USER_1, payable(USER_1), priceData, EMPTY_PREVIOUS_DATA
        );
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares / 2, USER_2, payable(USER_2), priceData, EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = DEPLOYER.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;

        skip(usdnProtocol.getValidationDeadline() + 1);

        vm.prank(DEPLOYER);
        echidna.validatePendingActions(10, 4000 ether);

        assertEq(DEPLOYER.balance, balanceBefore + securityDeposit * 2, "DEPLOYER balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit * 2, "protocol balance");
    }

    function test_canInitiateClosePosition() public {
        test_canFullOpenPosition();
        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        vm.prank(DEPLOYER);
        echidna.initiateClosePosition(securityDeposit, 0, 0, 4000 ether, 1 ether, 0);

        assertEq(
            uint8(usdnProtocol.getUserPendingAction(DEPLOYER).action),
            uint8(IUsdnProtocolTypes.ProtocolAction.ValidateClosePosition),
            "The user action should pending"
        );
    }

    function test_canFullDeposit() public {
        uint256 balanceDeployer = usdn.balanceOf(DEPLOYER);
        uint256 balanceProtocol = address(usdnProtocol).balance;

        vm.prank(DEPLOYER);
        echidna.fullDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 1000 ether);

        assertGt(usdn.balanceOf(DEPLOYER), balanceDeployer, "balance usdn");
        assertEq(address(usdnProtocol).balance, balanceProtocol, "protocol balance");
    }

    function test_canFullWithdrawal() public {
        assertGt(usdn.balanceOf(DEPLOYER), 0, "usdn balance before withdrawal");
        uint256 balanceProtocol = address(usdnProtocol).balance;
        uint256 usdnSharesBefore = usdn.sharesOf(DEPLOYER);

        vm.prank(DEPLOYER);
        echidna.fullWithdrawal(usdnShares, 10 ether, 0, 0, 1000 ether);

        assertEq(usdn.sharesOf(DEPLOYER), usdnSharesBefore - usdnShares, "usdn shares balance after withdrawal");
        assertEq(address(usdnProtocol).balance, balanceProtocol, "protocol balance");
    }

    function test_canFullOpenPosition() public {
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(DEPLOYER);

        vm.prank(DEPLOYER);
        echidna.fullOpenPosition(5 ether, 1000 ether, 10 ether, 0, 0, 2000 ether);

        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol, "protocol balance");
        assertEq(wsteth.balanceOf(DEPLOYER), balanceWstEthBefore, "wstETH balance");
    }

    function test_canFullClosePosition() public {
        test_canFullOpenPosition();
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);

        assertEq(
            uint8(usdnProtocol.getUserPendingAction(DEPLOYER).action),
            uint8(IUsdnProtocolTypes.ProtocolAction.None),
            "The user action should be none"
        );
        uint256 balanceBeforeWsteth = wsteth.balanceOf(DEPLOYER);

        vm.prank(DEPLOYER);
        echidna.fullClosePosition(securityDeposit, 0, 0, 2000 ether, 5 ether, 0);

        // the protocol fees are collected during all skip. So, wee have a delta of 1.05e15(0.105%)
        assertApproxEqRel(wsteth.balanceOf(DEPLOYER), balanceBeforeWsteth + 5 ether, 1.05e15, "wstETH balance");
        assertEq(
            uint8(usdnProtocol.getUserPendingAction(DEPLOYER).action),
            uint8(IUsdnProtocolTypes.ProtocolAction.None),
            "The user action should be none"
        );
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
            DEPLOYER,
            payable(DEPLOYER),
            echidna.NO_PERMIT2(),
            abi.encode(etherPrice),
            IUsdnProtocolTypes.PreviousActionsData(priceData, rawIndices)
        );
        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        usdnProtocol.validateOpenPosition(payable(DEPLOYER), abi.encode(etherPrice), EMPTY_PREVIOUS_DATA);
        usdnProtocol.initiateClosePosition{ value: securityDeposit }(
            posId, wstethOpenPositionAmount, DEPLOYER, payable(DEPLOYER), abi.encode(etherPrice), EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();

        uint256 balanceBefore = DEPLOYER.balance;
        uint256 balanceBeforeProtocol = address(usdnProtocol).balance;
        uint256 balanceWstEthBefore = wsteth.balanceOf(DEPLOYER);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(DEPLOYER);
        echidna.validateClosePosition(0, etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(DEPLOYER.balance, balanceBefore + securityDeposit, "DEPLOYER balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
        assertGt(wsteth.balanceOf(DEPLOYER), balanceWstEthBefore, "wstETH balance");
        assertLt(wsteth.balanceOf(DEPLOYER), balanceWstEthBefore + wstethOpenPositionAmount, "wstETH balance");
    }
}
