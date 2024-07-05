// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { MockOracleMiddleware } from "../../../test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Sdex } from "../../utils/Sdex.sol";
import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";
import { MockLiquidationRewardsManager } from "../mock/MockLiquidationRewardsManager.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../../src/UsdnProtocol/UsdnProtocol.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";

contract Setup is Test {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);
    uint256 public constant ACCOUNT_START_ETH_AMOUNT = 100 ether;
    //    uint256 public constant ACCOUNT_START_SDEX_AMOUNT = 10 ether;

    Sdex public immutable sdex = new Sdex();
    Weth public immutable weth = new Weth();
    WstETH public immutable wsteth = new WstETH();

    Permit2TokenBitfield.Bitfield constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);
    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    mapping(address => address[]) public destinationsToken;
    address[2] public validators = [DEPLOYER, ATTACKER];

    MockOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    UsdnProtocol public usdnProtocol;
    Rebalancer public rebalancer;

    bytes4[] public INITIATE_DEPOSIT_ERRORS = [IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector];

    constructor() payable {
        vm.warp(1_709_251_200);
        uint256 INIT_DEPOSIT_AMOUNT = 10 ether;
        uint256 INIT_LONG_AMOUNT = 10 ether;
        uint128 INITIAL_PRICE = 2000 ether; // 2000 USDN = 1 ETH

        uint256 ethAmount =
            (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT + ACCOUNT_START_ETH_AMOUNT) * wsteth.stEthPerToken() / 1 ether;
        vm.deal(address(this), ethAmount);
        (bool result,) = address(wsteth).call{ value: ethAmount }("");
        require(result, "WstETH mint failed");

        wsteth.transfer(DEPLOYER, ACCOUNT_START_ETH_AMOUNT);
        require(wsteth.balanceOf(DEPLOYER) == ACCOUNT_START_ETH_AMOUNT, "WstETH transfer failed");

        wstEthOracleMiddleware = new MockOracleMiddleware();

        liquidationRewardsManager = new MockLiquidationRewardsManager(IWstETH(wsteth), uint256(2 hours + 5 minutes));

        usdn = new Usdn(address(0), address(0));

        usdnProtocol =
            new UsdnProtocol(usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR);

        rebalancer = new Rebalancer(usdnProtocol);

        usdnProtocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        wsteth.approve(address(usdnProtocol), INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT);

        uint256 _desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
            bytes32(""),
            uint128(block.timestamp),
            IUsdnProtocolTypes.ProtocolAction.Initialize,
            abi.encode(INITIAL_PRICE)
        ).price / 2;

        // leverage approx 2x
        usdnProtocol.initialize(
            uint128(INIT_DEPOSIT_AMOUNT),
            uint128(INIT_LONG_AMOUNT),
            uint128(_desiredLiqPrice),
            abi.encode(INITIAL_PRICE)
        );

        destinationsToken[address(wsteth)] = [DEPLOYER, ATTACKER];

        //        vm.deal(DEPLOYER, ACCOUNT_START_ETH_AMOUNT);

        vm.prank(DEPLOYER);
        sdex.approve(address(usdnProtocol), type(uint256).max);
        vm.prank(ATTACKER);
        sdex.approve(address(usdnProtocol), type(uint256).max);

        vm.prank(DEPLOYER);
        wsteth.approve(address(usdnProtocol), type(uint256).max);
        vm.prank(ATTACKER);
        wsteth.approve(address(usdnProtocol), type(uint256).max);
    }
}

contract EchidnaAssert is Setup {
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initiateDeposit(
        uint128 amountWstETHRand,
        uint128 amountSdexRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand
    ) public {
        wsteth.mintAndApprove(msg.sender, amountWstETHRand, address(usdnProtocol), amountWstETHRand);
        sdex.mintAndApprove(msg.sender, amountSdexRand, address(usdnProtocol), amountSdexRand);
        vm.deal(msg.sender, ethRand);
        //        amountRand = uint128(bound(amountRand, 0, wsteth.balanceOf(msg.sender)));

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];

        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(2 ether);

        uint256 senderBalanceETH = address(msg.sender).balance;
        uint256 senderBalanceWstETH = wsteth.balanceOf(msg.sender);
        uint256 senderBalanceSdex = sdex.balanceOf(msg.sender);

        uint256 usdnProtocolBalanceETH = address(usdnProtocol).balance;
        uint256 usdnProtocolBalanceWstETH = wsteth.balanceOf(address(usdnProtocol));

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assertEq(address(msg.sender).balance, senderBalanceETH - securityDeposit);
            assertEq(wsteth.balanceOf(msg.sender), senderBalanceWstETH - amountWstETHRand);
            assertLt(sdex.balanceOf(msg.sender), senderBalanceSdex);

            assertEq(address(usdnProtocol).balance, usdnProtocolBalanceETH + securityDeposit);
            assertEq(wsteth.balanceOf(address(usdnProtocol)), usdnProtocolBalanceWstETH + amountWstETHRand);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_DEPOSIT_ERRORS);
        }
    }

    function _checkErrors(bytes memory err, bytes4[] storage errors) internal {
        bool expected = false;
        for (uint256 i = 0; i < errors.length; i++) {
            if (errors[i] == bytes4(err)) {
                expected = true;
                break;
            }
        }
        if (expected) {
            emit log_named_bytes("Expected error ", err);
            return;
        } else {
            emit log_named_bytes("DOS ", err);
            assert(false);
        }
    }
}
