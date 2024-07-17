// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { WstETH } from "../utils/WstEth.sol";

import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../src/UsdnProtocol/UsdnProtocol.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { FuzzingSuite } from "./FuzzingSuite.sol";

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

    function test_adminFunctions() public {
        echidna.setMinLeverage(10 ** 21 * 2);
        assertEq(usdnProtocol.getMinLeverage(), 10 ** 21 * 2, "minLeverage");

        echidna.setMaxLeverage(10 ** 21 * 9);
        assertEq(usdnProtocol.getMaxLeverage(), 10 ** 21 * 9, "maxLeverage");

        echidna.setValidationDeadline(0.5 days);
        assertEq(usdnProtocol.getValidationDeadline(), 0.5 days, "validationDeadline");

        echidna.setLiquidationPenalty(10);
        assertEq(usdnProtocol.getLiquidationPenalty(), 10, "liquidationPenalty");

        echidna.setSafetyMarginBps(10);
        assertEq(usdnProtocol.getSafetyMarginBps(), 10, "safetyMarginBps");

        echidna.setLiquidationIteration(8);
        assertEq(usdnProtocol.getLiquidationIteration(), 8, "liquidationIteration");

        echidna.setEMAPeriod(1 days);
        assertEq(usdnProtocol.getEMAPeriod(), 1 days, "emaPeriod");

        echidna.setFundingSF(500);
        assertEq(usdnProtocol.getFundingSF(), 500, "fundingSF");

        echidna.setProtocolFeeBps(5000);
        assertEq(usdnProtocol.getProtocolFeeBps(), 5000, "protocolFeeBps");

        echidna.setPositionFeeBps(1000);
        assertEq(usdnProtocol.getPositionFeeBps(), 1000, "positionFeeBps");

        echidna.setVaultFeeBps(1000);
        assertEq(usdnProtocol.getVaultFeeBps(), 1000, "vaultFeeBps");

        echidna.setRebalancerBonusBps(1000);
        assertEq(usdnProtocol.getRebalancerBonusBps(), 1000, "rebalancerBonusBps");

        echidna.setSdexBurnOnDepositRatio(1e4);
        assertEq(usdnProtocol.getSdexBurnOnDepositRatio(), 1e4, "sdexBurnOnDepositRatio");

        echidna.setSecurityDepositValue(1e19);
        assertEq(usdnProtocol.getSecurityDepositValue(), 1e19, "securityDepositValue");

        echidna.setFeeThreshold(1e30);
        assertEq(usdnProtocol.getFeeThreshold(), 1e30, "feeThreshold");

        echidna.setFeeCollector(DEPLOYER);
        assertEq(usdnProtocol.getFeeCollector(), DEPLOYER, "feeCollector");

        echidna.setExpoImbalanceLimits(5000, 0, 10_000, 1, -4900);
        assertEq(usdnProtocol.getOpenExpoImbalanceLimitBps(), 5000, "openExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getDepositExpoImbalanceLimitBps(), 0, "depositExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getWithdrawalExpoImbalanceLimitBps(), 10_000, "withdrawalExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getCloseExpoImbalanceLimitBps(), 1, "closeExpoImbalanceLimitBps");
        assertEq(usdnProtocol.getLongImbalanceTargetBps(), -4900, "longImbalanceTargetBps");

        echidna.setTargetUsdnPrice(1e18);
        assertEq(usdnProtocol.getTargetUsdnPrice(), 1e18, "targetUsdnPrice");

        echidna.setUsdnRebaseThreshold(1e30);
        assertEq(usdnProtocol.getUsdnRebaseThreshold(), 1e30, "usdnRebaseThreshold");

        echidna.setUsdnRebaseInterval(1e20);
        assertEq(usdnProtocol.getUsdnRebaseInterval(), 1e20, "usdnRebaseInterval");

        echidna.setMinLongPosition(1e24);
        assertEq(usdnProtocol.getMinLongPosition(), 1e24, "minLongPosition");
    }
}
