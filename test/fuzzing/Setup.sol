// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { RebalancerHandler } from "../unit/Rebalancer/utils/Handler.sol";
import { UsdnProtocolHandler } from "../unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "../unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { ADMIN, USER_1, USER_2 } from "../utils/Constants.sol";
import { IUsdnProtocolHandler } from "../utils/IUsdnProtocolHandler.sol";
import { Sdex } from "../utils/Sdex.sol";
import { Weth } from "../utils/WETH.sol";
import { WstETH } from "../utils/WstEth.sol";
import { ErrorsChecked } from "./helpers/ErrorsChecked.sol";
import { MockLiquidationRewardsManager } from "./mock/MockLiquidationRewardsManager.sol";

import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Permit2TokenBitfield } from "../../src/libraries/Permit2TokenBitfield.sol";
import { FeeCollector } from "../../src/utils/FeeCollector.sol";
import { InitializableReentrancyGuard } from "../../src/utils/InitializableReentrancyGuard.sol";

contract Setup is ErrorsChecked {
    address public constant DEPLOYER = USER_1;
    address public constant ATTACKER = USER_2;
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
    int24 internal _tickSpacing = 100; // tick spacing 100 = 1%
    FeeCollector public feeCollector;

    MockOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
    Usdn public usdn;
    IUsdnProtocolHandler public usdnProtocol;
    Rebalancer public rebalancer;

    struct ProtocolSnapshot {
        uint256 validatorEth;
        uint256 validatorWsteth;
        uint256 validatorUsdnShares;
        uint256 senderEth;
        uint256 senderWsteth;
        uint256 senderSdex;
        uint256 senderUsdnShares;
        uint256 toEth;
        uint256 toUsdnShares;
        uint256 toWsteth;
        uint256 protocolEth;
        uint256 protocolWsteth;
        uint256 protocolUsdnShares;
    }

    struct RebalancerSnapshot {
        uint256 senderEth;
        uint256 senderWsteth;
        uint256 toEth;
        uint256 toWsteth;
        uint256 rebalancerEth;
        uint256 rebalancerWsteth;
    }

    constructor() payable {
        vm.warp(1_709_251_200);
        wstEthOracleMiddleware = new MockOracleMiddleware();
        destinationsToken[address(wsteth)] = [DEPLOYER, ATTACKER];
        // todo: see if we want to fuzz chainlinkElapsedTimeLimit
        liquidationRewardsManager = new MockLiquidationRewardsManager(IWstETH(wsteth), uint256(2 hours + 5 minutes));
        usdn = new Usdn(address(0), address(0));

        bytes32 MINTER_ROLE = usdn.MINTER_ROLE();
        bytes32 REBASER_ROLE = usdn.REBASER_ROLE();

        IUsdnProtocolTypes.Roles memory roles = IUsdnProtocolTypes.Roles({
            setExternalAdmin: ADMIN,
            criticalFunctionsAdmin: ADMIN,
            setProtocolParamsAdmin: ADMIN,
            setUsdnParamsAdmin: ADMIN,
            setOptionsAdmin: ADMIN
        });

        feeCollector = new FeeCollector();
        UsdnProtocolHandler usdnProtocolImplementation = new UsdnProtocolHandler();
        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(usdnProtocolImplementation),
            abi.encodeCall(
                UsdnProtocolHandler.initializeStorageHandler,
                (
                    usdn,
                    sdex,
                    wsteth,
                    wstEthOracleMiddleware,
                    liquidationRewardsManager,
                    _tickSpacing,
                    address(feeCollector),
                    roles,
                    protocolFallback
                )
            )
        );
        usdnProtocol = IUsdnProtocolHandler(proxy);
        rebalancer = new RebalancerHandler(usdnProtocol);
        vm.prank(ADMIN);
        usdnProtocol.setRebalancer(rebalancer);
        usdn.grantRole(MINTER_ROLE, address(usdnProtocol));
        usdn.grantRole(REBASER_ROLE, address(usdnProtocol));
    }

    function getProtocolSnapshot(address validator, address to)
        internal
        view
        returns (ProtocolSnapshot memory snapshot)
    {
        snapshot.validatorEth = validator.balance;
        snapshot.validatorWsteth = wsteth.balanceOf(validator);
        snapshot.validatorUsdnShares = usdn.sharesOf(validator);
        snapshot.senderEth = msg.sender.balance;
        snapshot.senderWsteth = wsteth.balanceOf(msg.sender);
        snapshot.senderSdex = sdex.balanceOf(msg.sender);
        snapshot.senderUsdnShares = usdn.sharesOf(msg.sender);
        snapshot.protocolEth = address(usdnProtocol).balance;
        snapshot.protocolWsteth = wsteth.balanceOf(address(usdnProtocol));
        snapshot.protocolUsdnShares = usdn.sharesOf(address(usdnProtocol));
        snapshot.toEth = address(to).balance;
        snapshot.toUsdnShares = usdn.sharesOf(to);
        snapshot.toWsteth = wsteth.balanceOf(to);
    }

    function getRebalancerSnapshot(address dest) internal view returns (RebalancerSnapshot memory) {
        return RebalancerSnapshot({
            senderEth: msg.sender.balance,
            senderWsteth: wsteth.balanceOf(msg.sender),
            toEth: dest.balance,
            toWsteth: wsteth.balanceOf(dest),
            rebalancerEth: address(rebalancer).balance,
            rebalancerWsteth: wsteth.balanceOf(address(rebalancer))
        });
    }

    function _checkErrors(bytes memory err, bytes4[][] memory errorsArrays) internal virtual override {
        if (
            bytes4(err) == InitializableReentrancyGuard.InitializableReentrancyGuardUninitialized.selector
                && usdnProtocol.isInitialized()
        ) {
            emit log_named_bytes("Should be initialized: ", err);
            assert(false);
        } else if (
            bytes4(err) == InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector
                && !usdnProtocol.isInitialized()
        ) {
            emit log_named_bytes("Should not be initialized :", err);
            assert(false);
        }
        super._checkErrors(err, errorsArrays);
    }
}
