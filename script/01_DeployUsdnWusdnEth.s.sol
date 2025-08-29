// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { LiquidationRewardsManagerWusdn } from "../src/LiquidationRewardsManager/LiquidationRewardsManagerWusdn.sol";
import { WusdnToEthOracleMiddlewareWithPyth } from "../src/OracleMiddleware/WusdnToEthOracleMiddlewareWithPyth.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { UsdnNoRebase } from "../src/Usdn/UsdnNoRebase.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWusdn } from "../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnWusdnEthConfig } from "./deploymentConfigs/UsdnWusdnEthConfig.sol";
import { Utils } from "./utils/Utils.s.sol";

contract DeployUsdnWusdnEth is UsdnWusdnEthConfig, Script {
    IWusdn immutable WUSDN;
    Utils utils;

    constructor() {
        WUSDN = IWusdn(address(UNDERLYING_ASSET));
        utils = new Utils();
        vm.broadcast();
        (, SENDER,) = vm.readCallers();
    }

    /**
     * @notice Deploy the USDN ecosystem with WUSDN as the underlying token.
     * @return wusdnToEthOracleMiddleware_ The oracle middleware to get the price of the WUSDN in ETH.
     * @return liquidationRewardsManagerWusdn_ The liquidation rewards manager.
     * @return rebalancer_ The rebalancer.
     * @return usdnNoRebase_ The USDN token contract.
     * @return usdnProtocol_ The USDN protocol contract.
     */
    function run()
        public
        virtual
        returns (
            WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware_,
            LiquidationRewardsManagerWusdn liquidationRewardsManagerWusdn_,
            Rebalancer rebalancer_,
            UsdnNoRebase usdnNoRebase_,
            IUsdnProtocol usdnProtocol_
        )
    {
        utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        _setFeeCollector(SENDER);

        (wusdnToEthOracleMiddleware_, liquidationRewardsManagerWusdn_, usdnNoRebase_) =
            _deployAndSetPeripheralContracts();

        usdnProtocol_ = _deployProtocol(initStorage);
        _grantRequiredRoles(usdnProtocol_, usdnNoRebase_);

        rebalancer_ = _setRebalancer(usdnProtocol_);

        _initializeProtocol(usdnProtocol_, wusdnToEthOracleMiddleware_);
        _revokeRoles(usdnProtocol_);

        utils.validateProtocolConfig(usdnProtocol_, SENDER);
    }

    /**
     * @notice Deploy the oracle middleware, liquidation rewards manager and UsdnNoRebase contracts. Add them to the
     * initialization struct.
     * @dev As the USDN token doesn't rebase, there's no need to deploy the WUSDN contract, as wrapping is only useful
     * to avoid messing with the token balances in smart contracts.
     * @return wusdnToEthOracleMiddleware_ The oracle middleware that gets the price of the WUSDN in Eth.
     * @return liquidationRewardsManagerWusdn_ The liquidation rewards manager.
     * @return usdnNoRebase_ The USDN contract.
     */
    function _deployAndSetPeripheralContracts()
        internal
        returns (
            WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware_,
            LiquidationRewardsManagerWusdn liquidationRewardsManagerWusdn_,
            UsdnNoRebase usdnNoRebase_
        )
    {
        vm.startBroadcast();
        liquidationRewardsManagerWusdn_ = new LiquidationRewardsManagerWusdn(WUSDN);
        wusdnToEthOracleMiddleware_ = new WusdnToEthOracleMiddlewareWithPyth(
            PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WUSDN.USDN()), CHAINLINK_PRICE_VALIDITY
        );

        usdnNoRebase_ = new UsdnNoRebase("Synthetic ETH", "syntETH");
        vm.stopBroadcast();

        _setPeripheralContracts(wusdnToEthOracleMiddleware_, liquidationRewardsManagerWusdn_, usdnNoRebase_);
    }

    /**
     * @notice Deploy the USDN protocol.
     * @param initStorage The initialization parameters struct.
     * @return usdnProtocol_ The USDN protocol proxy.
     */
    function _deployProtocol(Types.InitStorage storage initStorage) internal returns (IUsdnProtocol usdnProtocol_) {
        // we need to allow external library linking and immutable variables in the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable,missing-initializer";

        vm.startBroadcast();

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback(MAX_SDEX_BURN_RATIO, MAX_MIN_LONG_POSITION);
        _setProtocolFallback(protocolFallback);

        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocolImpl.sol", abi.encodeCall(UsdnProtocolImpl.initializeStorage, initStorage), opts
        );

        vm.stopBroadcast();

        usdnProtocol_ = IUsdnProtocol(proxy);
    }

    /**
     * @notice Deploys and sets the rebalancer.
     * @param usdnProtocol The USDN protocol.
     * @return rebalancer_ The rebalancer.
     */
    function _setRebalancer(IUsdnProtocol usdnProtocol) internal returns (Rebalancer rebalancer_) {
        vm.startBroadcast();

        rebalancer_ = new Rebalancer(usdnProtocol);
        usdnProtocol.setRebalancer(rebalancer_);

        vm.stopBroadcast();
    }

    /**
     * @notice Initializes the USDN protocol with a ~2x leverage long position.
     * @param usdnProtocol The USDN protocol.
     * @param wusdnToEthOracleMiddleware The WstETH oracle middleware.
     */
    function _initializeProtocol(
        IUsdnProtocol usdnProtocol,
        WusdnToEthOracleMiddlewareWithPyth wusdnToEthOracleMiddleware
    ) internal {
        uint24 liquidationPenalty = usdnProtocol.getLiquidationPenalty();
        int24 tickSpacing = usdnProtocol.getTickSpacing();
        uint256 price = wusdnToEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), Types.ProtocolAction.Initialize, ""
        ).price;

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
        uint256 depositAmount = positionTotalExpo - INITIAL_LONG_AMOUNT;
        vm.startBroadcast();
        WUSDN.approve(address(usdnProtocol), depositAmount + INITIAL_LONG_AMOUNT);
        usdnProtocol.initialize(uint128(depositAmount), uint128(INITIAL_LONG_AMOUNT), desiredLiqPrice, "");
        vm.stopBroadcast();
    }

    /**
     * @dev Grants the required roles for the deployment.
     * @param usdnProtocol The deployed USDN protocol.
     * @param usdnNoRebase The USDN token of the protocol.
     */
    function _grantRequiredRoles(IUsdnProtocol usdnProtocol, UsdnNoRebase usdnNoRebase) internal {
        vm.startBroadcast();

        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, SENDER);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, SENDER);

        usdnNoRebase.transferOwnership(address(usdnProtocol));

        vm.stopBroadcast();
    }

    /**
     * @dev Revokes the roles that were only necessary during the deployment.
     * @param usdnProtocol The deployed USDN protocol.
     */
    function _revokeRoles(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();

        usdnProtocol.revokeRole(Constants.SET_EXTERNAL_ROLE, SENDER);
        usdnProtocol.revokeRole(Constants.ADMIN_SET_EXTERNAL_ROLE, SENDER);

        vm.stopBroadcast();
    }
}
