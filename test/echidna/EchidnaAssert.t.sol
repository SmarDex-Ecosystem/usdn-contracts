// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { MockOracleMiddleware } from "../../../test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { UsdnProtocol } from "../../src/UsdnProtocol/UsdnProtocol.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";
import { Sdex } from "../utils/Sdex.sol";
import { WstETH } from "../utils/WstEth.sol";
import { EchidnaAssert } from "./models/EchidnaAssert.sol";

contract TestEchidna is Test {
    EchidnaAssert public echidna;
    UsdnProtocol public usdnProtocol;
    MockOracleMiddleware public wstEthOracleMiddleware;
    WstETH public wsteth;
    Usdn public usdn;

    address internal DEPLOYER;
    address internal ATTACKER;

    uint152 internal usdnShares = 100_000 ether;

    function setUp() public {
        echidna = new EchidnaAssert();
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
        //        echidna.initiateDeposit(0.1 ether, 10 ether, 0.5 ether, 0, 0, 1000 ether);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(DEPLOYER);
        echidna.validateDeposit(0, price);

        assertGt(usdn.balanceOf(DEPLOYER), balanceDeployer, "balance usdn");
    }

    function test_canValidateWithdrawal() public {
        vm.deal(DEPLOYER, 10 ether);
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        vm.prank(DEPLOYER);
        usdn.approve(address(usdnProtocol), usdnShares);
        bytes memory priceData = abi.encode(4000 ether);

        vm.prank(DEPLOYER);
        usdnProtocol.initiateWithdrawal{ value: securityDeposit }(
            usdnShares,
            DEPLOYER,
            payable(DEPLOYER),
            priceData,
            IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) })
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
}
