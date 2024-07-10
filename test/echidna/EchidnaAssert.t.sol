// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { UsdnProtocol } from "../../src/UsdnProtocol/UsdnProtocol.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";

import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { EchidnaAssert } from "./models/EchidnaAssert.sol";

contract TestEchidna is Test {
    EchidnaAssert public echidna;
    UsdnProtocol public usdnProtocol;

    address internal DEPLOYER;
    address internal ATTACKER;

    function setUp() public {
        echidna = new EchidnaAssert();
        DEPLOYER = echidna.DEPLOYER();
        ATTACKER = echidna.ATTACKER();

        usdnProtocol = echidna.usdnProtocol();
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
        uint152 usdnShares = 0.1 ether;
        IUsdn usdn = usdnProtocol.getUsdn();
        vm.prank(address(usdnProtocol));
        usdn.mintShares(DEPLOYER, usdnShares);
        vm.prank(DEPLOYER);
        echidna.initiateWithdrawal(usdnShares, 10 ether, 0, 0, 1000 ether);

        IUsdnProtocolTypes.PendingAction memory action = usdnProtocol.getUserPendingAction(DEPLOYER);
        assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateWithdrawal, "action type");
        assertEq(action.to, DEPLOYER, "action to");
        assertEq(action.validator, DEPLOYER, "action validator");
        assertEq(action.var1, int24(Vault._calcWithdrawalAmountLSB(usdnShares)), "action amount LSB");
        assertEq(action.var2, Vault._calcWithdrawalAmountMSB(usdnShares), "action amount MSB");
    }
}
