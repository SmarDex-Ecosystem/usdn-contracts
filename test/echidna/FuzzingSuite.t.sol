// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";

import { USER_1, USER_2 } from "../utils/Constants.sol";
import { WstETH } from "../utils/WstEth.sol";
import { FuzzingSuite } from "./FuzzingSuite.sol";

import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../src/UsdnProtocol/UsdnProtocol.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract FuzzingSuiteTest is Test {
    FuzzingSuite public echidna;
    UsdnProtocol public usdnProtocol;
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

    function test_canInitiateOpen() public {
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
        uint256 balanceDeployer = usdn.balanceOf(DEPLOYER);
        vm.prank(DEPLOYER);
        echidna.initiateDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 1000 ether);

        skip(1 minutes);
        vm.prank(DEPLOYER);
        echidna.validateDeposit(0, 1000 ether);

        assertGt(usdn.balanceOf(DEPLOYER), balanceDeployer, "balance usdn");
    }

    function test_canValidateOpen() public {
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
        echidna.validateOpen(uint256(uint160(DEPLOYER)), etherPrice);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.None, "action type");
        assertEq(DEPLOYER.balance, balanceBefore + securityDeposit, "DEPLOYER balance");
        assertEq(address(usdnProtocol).balance, balanceBeforeProtocol - securityDeposit, "protocol balance");
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
}
