// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { UsdnProtocol } from "../../src/UsdnProtocol/UsdnProtocol.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";

import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { MockOracleMiddleware } from "../../../test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";
import { WstETH } from "../utils/WstEth.sol";
import { EchidnaAssert } from "./models/EchidnaAssert.sol";

contract TestEchidna is Test {
    EchidnaAssert public echidna;
    UsdnProtocol public usdnProtocol;
    WstETH public wsteth;
    MockOracleMiddleware public wstEthOracleMiddleware;

    address internal DEPLOYER;
    address internal ATTACKER;

    function setUp() public {
        echidna = new EchidnaAssert();
        DEPLOYER = echidna.DEPLOYER();
        ATTACKER = echidna.ATTACKER();

        usdnProtocol = echidna.usdnProtocol();
        wstEthOracleMiddleware = echidna.wstEthOracleMiddleware();
        wsteth = echidna.wsteth();
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

    function test_canValidateOpen() public {
        uint256 initialTotalExpo = usdnProtocol.getTotalExpo();
        uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();
        bytes memory priceData = abi.encode(4000 ether);
        vm.deal(DEPLOYER, 10 ether);
        vm.startPrank(DEPLOYER);
        (bool result,) = address(wsteth).call{ value: 5 ether }("");
        require(result, "WstETH mint failed");
        wsteth.approve(address(usdnProtocol), type(uint256).max);
        (, IUsdnProtocolTypes.PositionId memory posId) = usdnProtocol.initiateOpenPosition{ value: securityDeposit }(
            3 ether,
            500 ether,
            DEPLOYER,
            payable(DEPLOYER),
            Permit2TokenBitfield.Bitfield.wrap(0),
            priceData,
            IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) })
        );
        vm.stopPrank();

        (IUsdnProtocolTypes.Position memory tempPos,) = usdnProtocol.getLongPosition(posId);

        skip(wstEthOracleMiddleware.getValidationDelay() + 1);
        vm.prank(DEPLOYER);
        echidna.validateOpen(0, 4000 ether);

        (IUsdnProtocolTypes.Position memory pos,) = usdnProtocol.getLongPosition(posId);
        assertTrue(pos.validated, "validated");
        assertEq(pos.user, tempPos.user, "user");
        assertEq(pos.amount, tempPos.amount, "amount");
        assertEq(pos.timestamp, tempPos.timestamp, "timestamp");
        assertLt(pos.totalExpo, tempPos.totalExpo, "totalExpo should have decreased");

        IUsdnProtocolTypes.TickData memory tickData = usdnProtocol.getTickData(posId.tick);
        assertEq(tickData.totalExpo, pos.totalExpo, "total expo in tick");
        assertEq(usdnProtocol.getTotalExpo(), initialTotalExpo + pos.totalExpo, "total expo");
    }
}
