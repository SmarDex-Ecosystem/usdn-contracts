// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { WstETH } from "../../test/utils/WstEth.sol";
import { UsdnWstethConfig } from "../deploymentConfigs/UsdnWstethConfig.sol";
import { Utils } from "../utils/Utils.s.sol";

import { LiquidationRewardsManager } from "../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { MockWstEthOracleMiddleware } from "../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DeployUsdnWstethFork is UsdnWstethConfig, Script {
    uint256 price = 3000 ether;
    Utils utils;

    constructor() UsdnWstethConfig(vm.envOr("UNDERLYING_ADDRESS", address(WSTETH))) {
        utils = new Utils();
        price = vm.envOr("START_PRICE", price);
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
            MockWstEthOracleMiddleware wstEthOracleMiddleware_,
            LiquidationRewardsManager liquidationRewardsManager_,
            Rebalancer rebalancer_,
            Usdn usdn_,
            Wusdn wusdn_,
            IUsdnProtocol usdnProtocol_
        )
    {
        _setFeeCollector(msg.sender);

        (wstEthOracleMiddleware_, liquidationRewardsManager_, usdn_, wusdn_) = _deployAndSetPeripheralContracts();

        usdnProtocol_ = _deployProtocol(initStorage);

        rebalancer_ = _setRebalancerAndHandleUsdnRoles(usdnProtocol_, usdn_);

        _initializeProtocol(usdnProtocol_);

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
            MockWstEthOracleMiddleware wstEthOracleMiddleware_,
            LiquidationRewardsManager liquidationRewardsManager_,
            Usdn usdn_,
            Wusdn wusdn_
        )
    {
        vm.startBroadcast();
        liquidationRewardsManager_ = new LiquidationRewardsManager(WSTETH);
        wstEthOracleMiddleware_ = new MockWstEthOracleMiddleware(
            PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WSTETH), CHAINLINK_PRICE_VALIDITY
        );
        MockWstEthOracleMiddleware(wstEthOracleMiddleware_).setVerifySignature(false);
        MockWstEthOracleMiddleware(wstEthOracleMiddleware_).setWstethMockedPrice(price);
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
        vm.startBroadcast();

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
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
     * @return rebalancer_ The rebalancer.
     */
    function _setRebalancerAndHandleUsdnRoles(IUsdnProtocol usdnProtocol, Usdn usdn)
        internal
        returns (Rebalancer rebalancer_)
    {
        vm.startBroadcast();

        rebalancer_ = new Rebalancer(usdnProtocol);
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, msg.sender);

        usdnProtocol.setRebalancer(rebalancer_);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.MINTER_ROLE(), msg.sender);
        usdn.grantRole(usdn.REBASER_ROLE(), msg.sender);

        vm.stopBroadcast();
    }

    /**
     * @notice Initialize the USDN protocol with a ~2x leverage long position.
     * @param usdnProtocol The USDN protocol.
     */
    function _initializeProtocol(IUsdnProtocol usdnProtocol) internal {
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
