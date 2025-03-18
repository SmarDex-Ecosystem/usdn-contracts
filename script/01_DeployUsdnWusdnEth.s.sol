// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnWusdnEthConfig } from "./deploymentConfigs/UsdnWusdnEthConfig.sol";
import { Utils } from "./utils/Utils.s.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WusdnToEthOracleMiddleware } from "../src/OracleMiddleware/WusdnToEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { UsdnNoRebase } from "../src/Usdn/UsdnNoRebase.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IWusdn } from "../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DeployUsdnWusdnEth is UsdnWusdnEthConfig, Script {
    IWusdn immutable WUSDN;
    Utils utils;

    constructor() {
        WUSDN = IWusdn(address(UNDERLYING_ASSET));
        utils = new Utils();
    }

    /**
     * @notice Deploy the USDN ecosystem with Wusdn as the underlying token.
     * @return wusdnToEthOracleMiddleware_ The oracle middleware to get the price of the Wusdn in ETH.
     * @return liquidationRewardsManager_ The liquidation rewards manager.
     * @return rebalancer_ The rebalancer.
     * @return usdnNoRebase_ The USDN token contract.
     * @return usdnProtocol_ The USDN protocol contract.
     */
    function run()
        external
        returns (
            WusdnToEthOracleMiddleware wusdnToEthOracleMiddleware_,
            LiquidationRewardsManager liquidationRewardsManager_,
            Rebalancer rebalancer_,
            UsdnNoRebase usdnNoRebase_,
            IUsdnProtocol usdnProtocol_
        )
    {
        utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        _setFeeCollector(msg.sender);

        (wusdnToEthOracleMiddleware_, liquidationRewardsManager_, usdnNoRebase_) = _deployAndSetPeripheralContracts();

        usdnProtocol_ = _deployProtocol(initStorage);

        rebalancer_ = _setRebalancerAndHandleUsdnRoles(usdnProtocol_);

        _initializeProtocol(usdnProtocol_, wusdnToEthOracleMiddleware_);

        utils.validateProtocolConfig(usdnProtocol_, msg.sender);
    }

    /**
     * @notice Deploy the oracle middleware, liquidation rewards manager and UsdnNoRebase contracts. Add then to the
     * initialization struct.
     * @dev As the USDN token doesn't rebase, there's no need to deploy the WUSDN contract, as wrapping is only useful
     * to avoid messing with the token balances in smart contracts.
     * @return wusdnToEthOracleMiddleware_ The oracle middleware that gets the price of the Wusdn in Eth.
     * @return liquidationRewardsManager_ The liquidation rewards manager.
     * @return usdnNoRebase_ The USDN contract.
     */
    function _deployAndSetPeripheralContracts()
        internal
        returns (
            WusdnToEthOracleMiddleware wusdnToEthOracleMiddleware_,
            LiquidationRewardsManager liquidationRewardsManager_,
            UsdnNoRebase usdnNoRebase_
        )
    {
        vm.startBroadcast();
        // TODO needs the new LiquidationRewardsManager
        // This doesn't work, it's just so t can compile
        liquidationRewardsManager_ = new LiquidationRewardsManager(IWstETH(address(WUSDN)));
        wusdnToEthOracleMiddleware_ = new WusdnToEthOracleMiddleware(
            PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WUSDN.USDN()), CHAINLINK_PRICE_VALIDITY
        );
        // TODO decide of a name/symbol
        usdnNoRebase_ = new UsdnNoRebase("", "");
        vm.stopBroadcast();

        _setPeripheralContracts(wusdnToEthOracleMiddleware_, liquidationRewardsManager_, usdnNoRebase_);
    }

    /**
     * @notice Deploy the USDN protocol.
     * @param initStorage The initialization parameters struct.
     * @return usdnProtocol_ The USDN protocol proxy.
     */
    function _deployProtocol(Types.InitStorage storage initStorage) internal returns (IUsdnProtocol usdnProtocol_) {
        // we need to allow external library linking and immutable variables in the openzeppelin module
        Options memory opts;
        opts.unsafeAllow = "external-library-linking,state-variable-immutable";

        vm.startBroadcast();

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        _setProtocolFallback(protocolFallback);

        address proxy = Upgrades.deployUUPSProxy(
            "UsdnProtocolImpl.sol", abi.encodeCall(UsdnProtocolImpl.initializeStorage, (initStorage)), opts
        );

        vm.stopBroadcast();

        usdnProtocol_ = IUsdnProtocol(proxy);
    }

    /**
     * @notice Set the rebalancer and give the minting and rebasing roles to the USDN protocol.
     * @param usdnProtocol The USDN protocol.
     * @return rebalancer_ The rebalancer.
     */
    function _setRebalancerAndHandleUsdnRoles(IUsdnProtocol usdnProtocol) internal returns (Rebalancer rebalancer_) {
        vm.startBroadcast();

        rebalancer_ = new Rebalancer(usdnProtocol);
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.setRebalancer(rebalancer_);

        vm.stopBroadcast();
    }

    /**
     * @notice Initialize the USDN protocol with a ~2x leverage long position.
     * @param usdnProtocol The USDN protocol.
     * @param wusdnToEthOracleMiddleware The WstETH oracle middleware.
     */
    function _initializeProtocol(IUsdnProtocol usdnProtocol, WusdnToEthOracleMiddleware wusdnToEthOracleMiddleware)
        internal
    {
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
}
