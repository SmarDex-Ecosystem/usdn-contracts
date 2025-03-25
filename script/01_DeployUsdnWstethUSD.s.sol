// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { Options, Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnWstethUSDConfig } from "./deploymentConfigs/UsdnWstethUSDConfig.sol";
import { Utils } from "./utils/Utils.s.sol";

import { LiquidationRewardsManagerWstEth } from "../src/LiquidationRewardsManager/LiquidationRewardsManagerWstEth.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DeployUsdnWstethUSD is UsdnWstethUSDConfig, Script {
    IWstETH immutable WSTETH;
    Utils utils;

    constructor() {
        WSTETH = IWstETH(address(UNDERLYING_ASSET));
        utils = new Utils();
    }

    /**
     * @notice Deploy the USDN ecosystem with the WstETH as underlying
     * @return wstEthOracleMiddleware_ The WstETH oracle middleware
     * @return liquidationRewardsManager_ The liquidation rewards manager
     * @return rebalancer_ The rebalancer
     * @return usdn_ The USDN contract
     * @return wusdn_ The WUSDN contract
     * @return usdnProtocol_ The USDN protocol
     */
    function run()
        external
        returns (
            WstEthOracleMiddleware wstEthOracleMiddleware_,
            LiquidationRewardsManagerWstEth liquidationRewardsManager_,
            Rebalancer rebalancer_,
            Usdn usdn_,
            Wusdn wusdn_,
            IUsdnProtocol usdnProtocol_
        )
    {
        utils.validateProtocol("UsdnProtocolImpl", "UsdnProtocolFallback");

        _setFeeCollector(msg.sender);

        (wstEthOracleMiddleware_, liquidationRewardsManager_, usdn_, wusdn_) = _deployAndSetPeripheralContracts();

        usdnProtocol_ = _deployProtocol(initStorage);

        rebalancer_ = _setRebalancerAndHandleUsdnRoles(usdnProtocol_, usdn_);

        _initializeProtocol(usdnProtocol_, wstEthOracleMiddleware_);

        utils.validateProtocolConfig(usdnProtocol_, msg.sender);
    }

    /**
     * @notice Deploy the oracle middleware, liquidation rewards manager, USDN and WUSDN contracts. Add then to the
     * initialization struct.
     * @return wstEthOracleMiddleware_ The WstETH oracle middleware
     * @return liquidationRewardsManager_ The liquidation rewards manager
     * @return usdn_ The USDN contract
     * @return wusdn_ The WUSDN contract
     */
    function _deployAndSetPeripheralContracts()
        internal
        returns (
            WstEthOracleMiddleware wstEthOracleMiddleware_,
            LiquidationRewardsManagerWstEth liquidationRewardsManager_,
            Usdn usdn_,
            Wusdn wusdn_
        )
    {
        vm.startBroadcast();
        liquidationRewardsManager_ = new LiquidationRewardsManagerWstEth(WSTETH);
        wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
            PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WSTETH), CHAINLINK_PRICE_VALIDITY
        );
        usdn_ = new Usdn(address(0), address(0));
        wusdn_ = new Wusdn(usdn_);
        vm.stopBroadcast();

        _setPeripheralContracts(wstEthOracleMiddleware_, liquidationRewardsManager_, usdn_);
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

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback(MAX_SDEX_BURN_RATIO, MAX_MIN_LONG_POSITION);
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
    function _setRebalancerAndHandleUsdnRoles(IUsdnProtocol usdnProtocol, Usdn usdn)
        internal
        returns (Rebalancer rebalancer_)
    {
        vm.startBroadcast();

        rebalancer_ = new Rebalancer(usdnProtocol);
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.setRebalancer(rebalancer_);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));

        vm.stopBroadcast();
    }

    /**
     * @notice Initialize the USDN protocol with a ~2x leverage long position.
     * @param usdnProtocol The USDN protocol.
     * @param wstEthOracleMiddleware The WstETH oracle middleware.
     */
    function _initializeProtocol(IUsdnProtocol usdnProtocol, WstEthOracleMiddleware wstEthOracleMiddleware) internal {
        uint24 liquidationPenalty = usdnProtocol.getLiquidationPenalty();
        int24 tickSpacing = usdnProtocol.getTickSpacing();
        uint256 price = wstEthOracleMiddleware.parseAndValidatePrice(
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

        uint256 ethAmount = (depositAmount + INITIAL_LONG_AMOUNT + 10_000) * WSTETH.stEthPerToken() / 1 ether;

        vm.startBroadcast();
        (bool result,) = address(WSTETH).call{ value: ethAmount }(hex"");
        require(result, "Failed to mint wstETH");

        WSTETH.approve(address(usdnProtocol), depositAmount + INITIAL_LONG_AMOUNT);
        usdnProtocol.initialize(uint128(depositAmount), uint128(INITIAL_LONG_AMOUNT), desiredLiqPrice, "");
        vm.stopBroadcast();
    }
}
