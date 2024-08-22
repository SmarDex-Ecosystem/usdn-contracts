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
    address[3] public users = [USER_1, USER_2, ADMIN];
    address public constant FEE_COLLECTOR = address(0x00fee);
    Permit2TokenBitfield.Bitfield public constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);

    Sdex public sdex = new Sdex();
    Weth public weth = new Weth();
    WstETH public wsteth = new WstETH();

    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    mapping(address => address[]) public destinationsToken;
    IUsdnProtocolTypes.PositionId[] public posIds;
    int24 internal _tickSpacing = 100; // tick spacing 100 = 1%
    FeeCollector public feeCollector;

    MockOracleMiddleware public wstEthOracleMiddleware;
    MockLiquidationRewardsManager public liquidationRewardsManager;
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
        wstEthOracleMiddleware = new MockOracleMiddleware();
        destinationsToken[address(wsteth)] = [USER_1, USER_2];
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

    function getUsers() public view returns (address[3] memory) {
        return users;
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
