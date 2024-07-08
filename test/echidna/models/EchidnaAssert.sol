// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { MockOracleMiddleware } from "../../../test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";

import { UsdnProtocolHandler } from "../../unit/UsdnProtocol/utils/Handler.sol";
import { Sdex } from "../../utils/Sdex.sol";
import { Weth } from "../../utils/WETH.sol";
import { WstETH } from "../../utils/WstEth.sol";
import { MockLiquidationRewardsManager } from "../mock/MockLiquidationRewardsManager.sol";

import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../../src/UsdnProtocol/UsdnProtocol.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../../src/libraries/Permit2TokenBitfield.sol";

contract Setup is Test {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);
    uint256 public constant ACCOUNT_START_ETH_AMOUNT = 100 ether;
    uint256 public constant ACCOUNT_START_SDEX_AMOUNT = 10 ether;
    uint256 public constant CURRENT_PRICE = 2000 ether;

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
    UsdnProtocolHandler public usdnProtocol;
    Rebalancer public rebalancer;

    bytes4[] public INITIATE_DEPOSIT_ERRORS = [IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector];
    bytes4[] public INITIATE_OPEN_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        IUsdnProtocolErrors.UsdnProtocolLongPositionTooSmall.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidPendingAction.selector
    ];

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

        usdnProtocol = new UsdnProtocolHandler(
            usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR
        );

        rebalancer = new Rebalancer(usdnProtocol);

        usdnProtocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        wsteth.approve(address(usdnProtocol), INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT);

        uint256 _desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), IUsdnProtocolTypes.ProtocolAction.Initialize, abi.encode(INITIAL_PRICE)
        ).price / 2;

        // leverage approx 2x
        usdnProtocol.initialize(
            uint128(INIT_DEPOSIT_AMOUNT),
            uint128(INIT_LONG_AMOUNT),
            uint128(_desiredLiqPrice),
            abi.encode(INITIAL_PRICE)
        );

        destinationsToken[address(wsteth)] = [DEPLOYER, ATTACKER];

        vm.deal(DEPLOYER, ACCOUNT_START_ETH_AMOUNT);

        sdex.mintAndApprove(DEPLOYER, ACCOUNT_START_SDEX_AMOUNT, address(usdnProtocol), type(uint256).max);
        sdex.mintAndApprove(ATTACKER, ACCOUNT_START_SDEX_AMOUNT, address(usdnProtocol), type(uint256).max);

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

    struct OpenPositionParams {
        uint128 amountRand;
        uint128 liqPriceWithoutPenalty;
        uint128 expectedPosTotalExpo;
        uint256 validatorRand;
        address dest;
        address payable validator;
        bytes priceData;
        uint64 securityDeposit;
        uint256 senderBalanceETH;
        uint256 senderBalanceWstETH;
        uint256 usdnProtocolBalanceETH;
        uint256 usdnProtocolBalanceWstETH;
        int24 expectedTick;
    }

    struct ValueToCheckBefore {
        uint256 balance;
        uint256 protocolBalance;
        uint256 totalPositions;
        uint256 totalExpo;
        uint256 balanceLong;
    }

    function initiateDeposit(uint128 amountRand, uint256 destRand, uint256 validatorRand) public {
        amountRand = uint128(bound(amountRand, 0, wsteth.balanceOf(msg.sender)));

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];

        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(CURRENT_PRICE);

        uint64 securityDeposit = usdnProtocol.getSecurityDepositValue();

        uint256 senderBalanceETH = address(msg.sender).balance;
        uint256 senderBalanceWstETH = wsteth.balanceOf(msg.sender);
        uint256 senderBalanceSdex = sdex.balanceOf(msg.sender);

        uint256 usdnProtocolBalanceETH = address(usdnProtocol).balance;
        uint256 usdnProtocolBalanceWstETH = wsteth.balanceOf(address(usdnProtocol));

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: securityDeposit }(
            amountRand, dest, validator, NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        ) {
            assertEq(address(msg.sender).balance, senderBalanceETH - securityDeposit);
            assertEq(wsteth.balanceOf(msg.sender), senderBalanceWstETH - amountRand);
            assertLt(sdex.balanceOf(msg.sender), senderBalanceSdex);

            assertEq(address(usdnProtocol).balance, usdnProtocolBalanceETH + securityDeposit);
            assertEq(wsteth.balanceOf(address(usdnProtocol)), usdnProtocolBalanceWstETH + amountRand);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_DEPOSIT_ERRORS);
        }
    }

    function initiateOpenPosition(uint128 amountRand, uint256 destRand, uint256 validatorRand) public {
        (OpenPositionParams memory params, ValueToCheckBefore memory before) =
            getOpenPositionParams(amountRand, destRand, validatorRand);

        // vm.expectEmit();
        // emit IUsdnProtocolEvents.InitiatedOpenPosition(
        //     params.dest,
        //     params.validator,
        //     uint40(block.timestamp),
        //     params.expectedPosTotalExpo,
        //     uint128(amountRand),
        //     uint128(CURRENT_PRICE),
        //     IUsdnProtocolTypes.PositionId(int24(params.expectedTick), uint256(0), uint256(0))
        // );

        vm.prank(msg.sender);
        try usdnProtocol.initiateOpenPosition{ value: params.securityDeposit }(
            params.amountRand,
            params.amountRand / 2,
            params.dest,
            params.validator,
            NO_PERMIT2,
            params.priceData,
            EMPTY_PREVIOUS_DATA
        ) returns (bool, IUsdnProtocolTypes.PositionId memory posId) {
            // Optional, rechecked after
            assertEq(address(msg.sender).balance, params.senderBalanceETH - params.securityDeposit);
            assertEq(wsteth.balanceOf(msg.sender), params.senderBalanceWstETH - params.amountRand);

            assertEq(address(usdnProtocol).balance, params.usdnProtocolBalanceETH + params.securityDeposit);
            assertEq(wsteth.balanceOf(address(usdnProtocol)), params.usdnProtocolBalanceWstETH + params.amountRand);

            // check state after opening the position
            assertEq(posId.tick, params.expectedTick, "tick number");
            assertEq(posId.tickVersion, 0, "tick version");

            assertEq(posId.index, 0, "index");

            assertEq(wsteth.balanceOf(address(this)), before.balance - amountRand, "user wsteth balance");
            assertEq(
                wsteth.balanceOf(address(usdnProtocol)), before.protocolBalance + amountRand, "protocol wsteth balance"
            );
            assertEq(usdnProtocol.getTotalLongPositions(), before.totalPositions + 1, "total long positions");
            assertEq(usdnProtocol.getTotalExpo(), before.totalExpo + params.expectedPosTotalExpo, "protocol total expo");
            IUsdnProtocolTypes.TickData memory tickData = usdnProtocol.getTickData(params.expectedTick);
            assertEq(tickData.totalExpo, params.expectedPosTotalExpo, "total expo in tick");
            assertEq(tickData.totalPos, 1, "positions in tick");
            assertEq(usdnProtocol.getBalanceLong(), before.balanceLong + amountRand, "balance of long side");

            // // the pending action should not yet be actionable by a third party
            (IUsdnProtocolTypes.PendingAction[] memory pendingActions,) =
                usdnProtocol.getActionablePendingActions(address(0));
            assertEq(pendingActions.length, 0, "no pending action");

            IUsdnProtocolTypes.LongPendingAction memory action =
                usdnProtocol.i_toLongPendingAction(usdnProtocol.getUserPendingAction(params.validator));
            assertTrue(action.action == IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition, "action type");
            assertEq(action.timestamp, block.timestamp, "action timestamp");
            assertEq(action.to, params.dest, "action to"); // not sure of dest, should be to
            assertEq(action.validator, params.validator, "action validator");
            assertEq(action.tick, params.expectedTick, "action tick");
            assertEq(action.tickVersion, 0, "action tickVersion");
            assertEq(action.index, 0, "action index");

            // the pending action should be actionable after the validation deadline
            skip(usdnProtocol.getValidationDeadline() + 1);
            (pendingActions,) = usdnProtocol.getActionablePendingActions(address(0));
            action = usdnProtocol.i_toLongPendingAction(pendingActions[0]);
            assertEq(action.to, params.dest, "pending action to");
            assertEq(action.validator, params.validator, "pending action validator");

            IUsdnProtocolTypes.Position memory position;
            (position,) = usdnProtocol.getLongPosition(posId);
            assertFalse(position.validated, "pos validated");
            assertEq(position.user, params.dest, "user position");
            assertEq(position.timestamp, action.timestamp, "timestamp position");
            assertEq(position.amount, uint128(amountRand), "amount position");
            assertEq(position.totalExpo, params.expectedPosTotalExpo, "totalExpo position");
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_OPEN_ERRORS);
        }
    }

    function getOpenPositionParams(uint128 amountRand, uint256 destRand, uint256 validatorRand)
        internal
        view
        returns (OpenPositionParams memory params, ValueToCheckBefore memory before)
    {
        params.amountRand = uint128(bound(amountRand, 0, wsteth.balanceOf(msg.sender)));
        uint256 destRandBounded = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        params.dest = destinationsToken[address(wsteth)][destRandBounded];
        params.validatorRand = bound(validatorRand, 0, validators.length - 1);
        params.validator = payable(validators[params.validatorRand]);
        params.priceData = abi.encode(CURRENT_PRICE);
        params.securityDeposit = usdnProtocol.getSecurityDepositValue();
        params.senderBalanceETH = address(msg.sender).balance;
        params.senderBalanceWstETH = wsteth.balanceOf(msg.sender);
        params.usdnProtocolBalanceETH = address(usdnProtocol).balance;
        params.usdnProtocolBalanceWstETH = wsteth.balanceOf(address(usdnProtocol));
        params.expectedTick = usdnProtocol.getEffectiveTickForPrice(params.amountRand / 2);
        params.liqPriceWithoutPenalty =
            usdnProtocol.getEffectivePriceForTick(usdnProtocol.i_calcTickWithoutPenalty(params.expectedTick));
        params.expectedPosTotalExpo = usdnProtocol.i_calcPositionTotalExpo(
            uint128(amountRand), uint128(CURRENT_PRICE), params.liqPriceWithoutPenalty
        );

        before = ValueToCheckBefore({
            balance: wsteth.balanceOf(address(this)),
            protocolBalance: wsteth.balanceOf(address(usdnProtocol)),
            totalPositions: usdnProtocol.getTotalLongPositions(),
            totalExpo: usdnProtocol.getTotalExpo(),
            balanceLong: uint256(usdnProtocol.i_longAssetAvailable(uint128(CURRENT_PRICE)))
        });
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
