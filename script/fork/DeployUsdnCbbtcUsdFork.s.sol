// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { MockChainlinkOnChain } from "../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { UsdnCbbtcUsdConfig } from "../deploymentConfigs/UsdnCbbtcUsdConfig.sol";
import { Utils } from "../utils/Utils.s.sol";

import { LiquidationRewardsManagerCbBTC } from "../../src/LiquidationRewardsManager/LiquidationRewardsManagerCbBTC.sol";
import { MockOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/mock/MockOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DeployUsdnGenericFork is UsdnCbbtcUsdConfig, Script {
    address immutable CHAINLINK_PRICE_MOCKED = address(new MockChainlinkOnChain());
    uint256 price = 100_000 ether;
    Utils utils;

    constructor() {
        UNDERLYING_ASSET = IERC20Metadata(vm.envOr("UNDERLYING_ADDRESS", address(CBBTC)));
        utils = new Utils();
        price = vm.envOr("START_PRICE", price);
        vm.startBroadcast();
        (, SENDER,) = vm.readCallers();
        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the USDN ecosystem with the cbBTC as underlying
     * @return oracleMiddleware_ The oracle middleware
     * @return liquidationRewardsManager_ The liquidation rewards manager
     * @return rebalancer_ The rebalancer
     * @return usdn_ The USDN contract
     * @return wusdn_ The WUSDN contract
     * @return usdnProtocol_ The USDN protocol
     */
    function run()
        external
        returns (
            MockOracleMiddlewareWithPyth oracleMiddleware_,
            LiquidationRewardsManagerCbBTC liquidationRewardsManager_,
            Rebalancer rebalancer_,
            Usdn usdn_,
            Wusdn wusdn_,
            IUsdnProtocol usdnProtocol_,
            address underlying_,
            address sdex_
        )
    {
        require(CBBTC.balanceOf(SENDER) > 0, "Sender does not have any CBBTC");

        _setFeeCollector(SENDER);

        (oracleMiddleware_, liquidationRewardsManager_, usdn_, wusdn_) = _deployAndSetPeripheralContracts();

        usdnProtocol_ = _deployProtocol(initStorage);

        rebalancer_ = _setRebalancerAndHandleUsdnRoles(usdnProtocol_, usdn_);

        _initializeProtocol(usdnProtocol_);

        utils.validateProtocolConfig(usdnProtocol_, SENDER);

        underlying_ = address(UNDERLYING_ASSET);

        sdex_ = address(SDEX);
    }

    /**
     * @notice Deploy the oracle middleware, liquidation rewards manager, USDN and WUSDN contracts. Add then to the
     * initialization struct.
     * @return oracleMiddleware_ The oracle middleware
     * @return liquidationRewardsManager_ The liquidation rewards manager
     * @return usdn_ The USDN contract
     * @return wusdn_ The WUSDN contract
     */
    function _deployAndSetPeripheralContracts()
        internal
        virtual
        returns (
            MockOracleMiddlewareWithPyth oracleMiddleware_,
            LiquidationRewardsManagerCbBTC liquidationRewardsManager_,
            Usdn usdn_,
            Wusdn wusdn_
        )
    {
        vm.startBroadcast();
        liquidationRewardsManager_ = new LiquidationRewardsManagerCbBTC(CBBTC);
        oracleMiddleware_ = new MockOracleMiddlewareWithPyth(
            PYTH_ADDRESS, PYTH_BTC_FEED_ID, CHAINLINK_PRICE_MOCKED, CHAINLINK_PRICE_VALIDITY
        );
        MockOracleMiddlewareWithPyth(oracleMiddleware_).setVerifySignature(false);
        MockOracleMiddlewareWithPyth(oracleMiddleware_).setMockedPrice(price);
        usdn_ = new Usdn(address(0), address(0));
        wusdn_ = new Wusdn(usdn_);
        vm.stopBroadcast();

        _setPeripheralContracts(oracleMiddleware_, liquidationRewardsManager_, usdn_);
    }

    /**
     * @notice Deploy the USDN protocol.
     * @param initStorage The initialization parameters struct.
     * @return usdnProtocol_ The USDN protocol proxy.
     */
    function _deployProtocol(Types.InitStorage storage initStorage)
        internal
        virtual
        returns (IUsdnProtocol usdnProtocol_)
    {
        vm.startBroadcast();

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback(MAX_SDEX_BURN_RATIO, MAX_MIN_LONG_POSITION);
        _setProtocolFallback(protocolFallback);

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(new UsdnProtocolImpl()), abi.encodeCall(UsdnProtocolImpl.initializeStorage, initStorage)
        );

        vm.stopBroadcast();

        usdnProtocol_ = IUsdnProtocol(proxy);
    }

    /**
     * @notice Set the rebalancer and give the minting and rebasing roles to the USDN protocol.
     * @param usdnProtocol The USDN protocol.
     * @param usdn The USDN token.
     * @return rebalancer_ The rebalancer.
     */
    function _setRebalancerAndHandleUsdnRoles(IUsdnProtocol usdnProtocol, Usdn usdn)
        internal
        virtual
        returns (Rebalancer rebalancer_)
    {
        vm.startBroadcast();

        rebalancer_ = new Rebalancer(usdnProtocol);
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, SENDER);

        usdnProtocol.setRebalancer(rebalancer_);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.MINTER_ROLE(), SENDER);
        usdn.grantRole(usdn.REBASER_ROLE(), SENDER);

        vm.stopBroadcast();
    }

    /**
     * @notice Initialize the USDN protocol with a ~2x leverage long position.
     * @param usdnProtocol The USDN protocol.
     */
    function _initializeProtocol(IUsdnProtocol usdnProtocol) internal virtual {
        uint24 liquidationPenalty = usdnProtocol.getLiquidationPenalty();
        int24 tickSpacing = usdnProtocol.getTickSpacing();

        // we want a leverage of ~2x so we get the current price from the middleware and divide it by two
        uint128 desiredLiqPrice = uint128(price / 2);
        // get the liquidation price with the tick rounding
        uint128 liqPriceWithoutPenalty = usdnProtocol.getLiqPriceFromDesiredLiqPrice(
            desiredLiqPrice, price, 0, HugeUint.wrap(0), tickSpacing, liquidationPenalty
        );
        // get the total exposure of the wanted long position
        uint256 positionTotalExpo =
            FixedPointMathLib.fullMulDiv(INITIAL_LONG_AMOUNT, price, price - liqPriceWithoutPenalty);
        // get the amount to deposit to reach a balanced state
        uint256 vaultAmount = positionTotalExpo - INITIAL_LONG_AMOUNT;

        uint256 initAmount = (vaultAmount + INITIAL_LONG_AMOUNT + 10_000);

        require(CBBTC.balanceOf(SENDER) >= initAmount, "Not enough CBBTC to initialize the protocol");

        vm.startBroadcast();
        CBBTC.approve(address(usdnProtocol), vaultAmount + INITIAL_LONG_AMOUNT);
        usdnProtocol.initialize(uint128(vaultAmount), uint128(INITIAL_LONG_AMOUNT), desiredLiqPrice, "");
        vm.stopBroadcast();
    }
}
