// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { MockChainlinkOnChain } from "../unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { MockPyth } from "../unit/Middlewares/utils/MockPyth.sol";
import { UsdnProtocolHandler } from "../unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { ADMIN, DEPLOYER, PYTH_ETH_USD, REDSTONE_ETH_USD } from "../utils/Constants.sol";
import { Sdex } from "../utils/Sdex.sol";
import { Weth } from "../utils/WETH.sol";
import { WstETH } from "../utils/WstEth.sol";
import { ErrorsChecked } from "./helpers/ErrorsChecked.sol";
import { MockLiquidationRewardsManager } from "./mock/MockLiquidationRewardsManager.sol";

import { WstEthOracleMiddleware } from "../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";

import { LiquidationRewardsManager } from "../../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { UsdnProtocolFallback } from "../../src/UsdnProtocol/UsdnProtocolFallback.sol";

import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";
import { IUsdnProtocolHandler } from "../utils/IUsdnProtocolHandler.sol";

contract Setup is ErrorsChecked {
    address public constant DEPLOYER = address(0x10000);
    address public constant ATTACKER = address(0x20000);
    address public constant FEE_COLLECTOR = address(0x00fee);
    Permit2TokenBitfield.Bitfield public constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);

    Sdex public sdex;
    Weth public weth;
    WstETH public wsteth;
    MockPyth public mockPyth;
    MockChainlinkOnChain public mockChainlinkOnChain;

    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    mapping(address => address[]) public destinationsToken;
    address[2] public validators = [DEPLOYER, ATTACKER];
    IUsdnProtocolTypes.PositionId[] public posIds;

    WstEthOracleMiddleware public oracleMiddleware;
    LiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    IUsdnProtocolHandler public usdnProtocol;
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

        wsteth = new WstETH();
        sdex = new Sdex();
        mockPyth = new MockPyth();
        mockChainlinkOnChain = new MockChainlinkOnChain();
        mockChainlinkOnChain.setLastPublishTime(1_704_092_400 - 10 minutes);
        // this is the stETH/USD oracle, we need to convert the initialPrice
        mockChainlinkOnChain.setLastPrice(int256(wsteth.getStETHByWstETH(uint256(2000 ether / 10 ** (18 - 8)))));
        oracleMiddleware = new WstEthOracleMiddleware(
            address(mockPyth), PYTH_ETH_USD, REDSTONE_ETH_USD, address(mockChainlinkOnChain), address(wsteth), 1 hours
        );
        vm.warp(1_704_092_400);
        liquidationRewardsManager = new LiquidationRewardsManager(address(new MockChainlinkOnChain()), wsteth, 2 days);

        vm.deal(address(this), 100_000_000_000_000 ether);
        (bool success,) = address(wsteth).call{ value: DEPLOYER.balance * 9 / 10 }("");
        require(success, "DEPLOYER wstETH mint failed");
        usdn = new Usdn(address(0), address(0));

        IUsdnProtocolTypes.Roles memory roles = IUsdnProtocolTypes.Roles({
            setExternalAdmin: ADMIN,
            criticalFunctionsAdmin: ADMIN,
            setProtocolParamsAdmin: ADMIN,
            setUsdnParamsAdmin: ADMIN,
            setOptionsAdmin: ADMIN
        });

        UsdnProtocolHandler implementation = new UsdnProtocolHandler();
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        usdnProtocol = IUsdnProtocolHandler(address(implementation));
        usdnProtocol.initializeStorage(
            usdn,
            sdex,
            wsteth,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN,
            roles,
            protocolFallback
        );

        rebalancer = new Rebalancer(usdnProtocol);
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        wsteth.approve(address(usdnProtocol), type(uint256).max);
        // leverage approx 2x
        usdnProtocol.initialize{
            value: oracleMiddleware.validationCost("", IUsdnProtocolTypes.ProtocolAction.Initialize)
        }(99.474794733414559008 ether, 100 ether, 1000 ether, "");
        vm.prank(roles.setExternalAdmin);
        usdnProtocol.setRebalancer(rebalancer);

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
