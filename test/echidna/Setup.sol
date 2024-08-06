// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolHandler } from "../unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { Sdex } from "../utils/Sdex.sol";
import { Weth } from "../utils/WETH.sol";
import { WstETH } from "../utils/WstEth.sol";
import { ErrorsChecked } from "./helpers/ErrorsChecked.sol";
import { MockLiquidationRewardsManager } from "./mock/MockLiquidationRewardsManager.sol";

import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";

contract Setup is ErrorsChecked {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);
    Permit2TokenBitfield.Bitfield public constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);

    Sdex public sdex = new Sdex();
    Weth public weth = new Weth();
    WstETH public wsteth = new WstETH();

    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    mapping(address => address[]) public destinationsToken;
    address[2] public validators = [DEPLOYER, ATTACKER];
    IUsdnProtocolTypes.PositionId[] public posIds;

    MockOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    UsdnProtocolHandler public usdnProtocol;
    Rebalancer public rebalancer;

    struct BalancesSnapshot {
        uint256 validatorEth;
        uint256 validatorWsteth;
        uint256 validatorUsdnShares;
        uint256 senderEth;
        uint256 senderWsteth;
        uint256 senderSdex;
        uint256 senderUsdnShares;
        uint256 protocolEth;
        uint256 protocolWsteth;
        uint256 protocolUsdnShares;
        uint256 toEth;
        uint256 toUsdnShares;
        uint256 toWsteth;
    }

    constructor() payable {
        vm.warp(1_709_251_200);
        //TODO see to fuzz these data
        uint256 INIT_DEPOSIT_AMOUNT = 300 ether;
        uint256 INIT_LONG_AMOUNT = 300 ether;
        uint128 INITIAL_PRICE = 2000 ether; // 2000 USDN = 1 ETH

        uint256 ethAmount = (INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT) * wsteth.stEthPerToken() / 1 ether;
        vm.deal(DEPLOYER, ethAmount);
        vm.prank(DEPLOYER);
        (bool result,) = address(wsteth).call{ value: ethAmount }("");
        require(result, "WstETH mint failed");

        vm.prank(DEPLOYER);
        wstEthOracleMiddleware = new MockOracleMiddleware();

        vm.prank(DEPLOYER);
        liquidationRewardsManager = new MockLiquidationRewardsManager(IWstETH(wsteth), uint256(2 hours + 5 minutes));

        vm.prank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        bytes32 MINTER_ROLE = usdn.MINTER_ROLE();
        bytes32 REBASER_ROLE = usdn.REBASER_ROLE();

        vm.prank(DEPLOYER);
        usdnProtocol = new UsdnProtocolHandler(
            usdn, sdex, wsteth, wstEthOracleMiddleware, liquidationRewardsManager, 100, FEE_COLLECTOR
        );

        vm.prank(DEPLOYER);
        rebalancer = new Rebalancer(usdnProtocol);

        vm.prank(DEPLOYER);
        usdnProtocol.setRebalancer(rebalancer);

        vm.prank(DEPLOYER);
        usdn.grantRole(MINTER_ROLE, address(usdnProtocol));

        vm.prank(DEPLOYER);
        usdn.grantRole(REBASER_ROLE, address(usdnProtocol));

        vm.prank(DEPLOYER);
        wsteth.approve(address(usdnProtocol), INIT_DEPOSIT_AMOUNT + INIT_LONG_AMOUNT);

        uint256 _desiredLiqPrice = wstEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), IUsdnProtocolTypes.ProtocolAction.Initialize, abi.encode(INITIAL_PRICE)
        ).price / 2;

        // leverage approx 2x
        vm.prank(DEPLOYER);
        usdnProtocol.initialize(
            uint128(INIT_DEPOSIT_AMOUNT),
            uint128(INIT_LONG_AMOUNT),
            uint128(_desiredLiqPrice),
            abi.encode(INITIAL_PRICE)
        );

        destinationsToken[address(wsteth)] = [DEPLOYER, ATTACKER];
    }

    function getBalances(address validator, address to) internal view returns (BalancesSnapshot memory) {
        return BalancesSnapshot({
            validatorEth: validator.balance,
            validatorWsteth: wsteth.balanceOf(validator),
            validatorUsdnShares: usdn.sharesOf(validator),
            senderEth: msg.sender.balance,
            senderWsteth: wsteth.balanceOf(msg.sender),
            senderSdex: sdex.balanceOf(msg.sender),
            senderUsdnShares: usdn.sharesOf(msg.sender),
            protocolEth: address(usdnProtocol).balance,
            protocolWsteth: wsteth.balanceOf(address(usdnProtocol)),
            protocolUsdnShares: usdn.sharesOf(address(usdnProtocol)),
            toEth: address(to).balance,
            toUsdnShares: usdn.sharesOf(to),
            toWsteth: wsteth.balanceOf(to)
        });
    }
}
