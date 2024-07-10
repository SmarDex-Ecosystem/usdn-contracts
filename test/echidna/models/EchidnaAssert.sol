// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

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
import { SignedMath } from "../../../src/libraries/SignedMath.sol";

contract Setup is Test {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);

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

    bytes4[] public INITIATE_DEPOSIT_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached.selector,
        IUsdnProtocolErrors.UsdnProtocolDepositTooSmall.selector,
        IUsdnProtocolErrors.UsdnProtocolInvalidLongExpo.selector,
        IUsdnProtocolErrors.UsdnProtocolPendingAction.selector,
        FixedPointMathLib.FullMulDivFailed.selector
    ];
    bytes4[] public INITIATE_WITHDRAWAL_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressTo.selector,
        IUsdnProtocolErrors.UsdnProtocolSecurityDepositTooLow.selector,
        IUsdnProtocolErrors.UsdnProtocolZeroAmount.selector,
        SignedMath.SignedMathDivideByZero.selector
    ];

    bytes4[] public VALIDATE_WITHDRAWAL_ERRORS = [
        IUsdnProtocolErrors.UsdnProtocolInvalidAddressValidator.selector,
        IUsdnProtocolErrors.UsdnProtocolNoPendingAction.selector
    ];

    constructor() payable {
        vm.warp(1_709_251_200);
        //TODO see to fuzz these data
        uint256 INIT_DEPOSIT_AMOUNT = 10 ether;
        uint256 INIT_LONG_AMOUNT = 10 ether;
        uint128 INITIAL_PRICE = 2000 ether; // 2000 USDN = 1 ETH

        uint256 ethAmount = (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT) * wsteth.stEthPerToken() / 1 ether;
        vm.deal(address(this), ethAmount);
        (bool result,) = address(wsteth).call{ value: ethAmount }("");
        require(result, "WstETH mint failed");

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
    }
}

contract EchidnaAssert is Setup {
    struct InitiateDepositBalanceBefore {
        uint256 senderETH;
        uint256 senderWstETH;
        uint256 senderSdex;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolWstETH;
    }

    struct InitiateWithdrawalBalanceBefore {
        uint256 senderETH;
        uint256 senderUsdn;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolUsdn;
    }

    struct ValidateWithdrawalBalanceBefore {
        uint256 senderETH;
        uint256 senderWstETH;
        uint256 usdnProtocolETH;
        uint256 usdnProtocolUsdn;
        uint256 usdnProtocolWstETH;
    }
    /* -------------------------------------------------------------------------- */
    /*                             USDN Protocol                                  */
    /* -------------------------------------------------------------------------- */

    function initiateDeposit(
        uint128 amountWstETHRand,
        uint128 amountSdexRand,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 currentPrice
    ) public {
        wsteth.mintAndApprove(msg.sender, amountWstETHRand, address(usdnProtocol), amountWstETHRand);
        sdex.mintAndApprove(msg.sender, amountSdexRand, address(usdnProtocol), amountSdexRand);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];

        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(currentPrice);

        InitiateDepositBalanceBefore memory balanceBefore = InitiateDepositBalanceBefore({
            senderETH: address(msg.sender).balance,
            senderWstETH: wsteth.balanceOf(msg.sender),
            senderSdex: sdex.balanceOf(msg.sender),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolWstETH: wsteth.balanceOf(address(usdnProtocol))
        });

        vm.prank(msg.sender);
        try usdnProtocol.initiateDeposit{ value: ethRand }(
            amountWstETHRand, dest, validator, NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balanceBefore.senderETH - securityDeposit);
            assert(wsteth.balanceOf(msg.sender) == balanceBefore.senderWstETH - amountWstETHRand);
            assert(sdex.balanceOf(msg.sender) < balanceBefore.senderSdex);
            assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH + securityDeposit);
            assert(wsteth.balanceOf(address(usdnProtocol)) == balanceBefore.usdnProtocolWstETH + amountWstETHRand);
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

    function initiateWithdrawal(
        uint152 usdnShares,
        uint256 ethRand,
        uint256 destRand,
        uint256 validatorRand,
        uint256 currentPrice
    ) public {
        vm.prank(msg.sender);
        usdn.approve(address(usdnProtocol), usdnShares);
        vm.deal(msg.sender, ethRand);

        destRand = bound(destRand, 0, destinationsToken[address(wsteth)].length - 1);
        address dest = destinationsToken[address(wsteth)][destRand];

        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(currentPrice);

        InitiateWithdrawalBalanceBefore memory balanceBefore = InitiateWithdrawalBalanceBefore({
            senderETH: address(msg.sender).balance,
            senderUsdn: usdn.sharesOf(msg.sender),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolUsdn: usdn.sharesOf(address(usdnProtocol))
        });

        vm.prank(msg.sender);
        try usdnProtocol.initiateWithdrawal{ value: ethRand }(
            usdnShares, dest, validator, priceData, EMPTY_PREVIOUS_DATA
        ) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balanceBefore.senderETH - securityDeposit);
            assert(usdn.sharesOf(msg.sender) == balanceBefore.senderUsdn - usdnShares);

            assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH + securityDeposit);
            assert(usdn.sharesOf(address(usdnProtocol)) == balanceBefore.usdnProtocolUsdn + usdnShares);
        } catch (bytes memory err) {
            _checkErrors(err, INITIATE_WITHDRAWAL_ERRORS);
        }
    }

    function validateWithdrawal(uint256 ethRand, uint256 validatorRand, uint256 currentPrice) public {
        validatorRand = bound(validatorRand, 0, validators.length - 1);
        address payable validator = payable(validators[validatorRand]);

        bytes memory priceData = abi.encode(currentPrice);

        ValidateWithdrawalBalanceBefore memory balanceBefore = ValidateWithdrawalBalanceBefore({
            senderETH: address(msg.sender).balance,
            senderWstETH: wsteth.balanceOf(msg.sender),
            usdnProtocolETH: address(usdnProtocol).balance,
            usdnProtocolUsdn: usdn.sharesOf(address(usdnProtocol)),
            usdnProtocolWstETH: wsteth.balanceOf(address(usdnProtocol))
        });

        vm.prank(msg.sender);
        try usdnProtocol.validateWithdrawal{ value: ethRand }(validator, priceData, EMPTY_PREVIOUS_DATA) {
            uint256 securityDeposit = usdnProtocol.getSecurityDepositValue();

            assert(address(msg.sender).balance == balanceBefore.senderETH + securityDeposit);
            assert(wsteth.balanceOf(msg.sender) > balanceBefore.senderWstETH);

            assert(address(usdnProtocol).balance == balanceBefore.usdnProtocolETH - securityDeposit);
            assert(usdn.sharesOf(msg.sender) < balanceBefore.usdnProtocolUsdn);
            assert(usdn.sharesOf(address(usdnProtocol)) < balanceBefore.usdnProtocolWstETH);
        } catch (bytes memory err) {
            _checkErrors(err, VALIDATE_WITHDRAWAL_ERRORS);
        }
    }
}
