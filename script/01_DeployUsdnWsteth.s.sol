// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnWstethConfig } from "./deploymentConfigs/UsdnWsteth.sol";
import { DeployProtocolProd } from "./utils/DeployProtocolProd.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DeployUsdnWsteth is DeployProtocolProd, UsdnWstethConfig {
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
            LiquidationRewardsManager liquidationRewardsManager_,
            Rebalancer rebalancer_,
            Usdn usdn_,
            Wusdn wusdn_,
            IUsdnProtocol usdnProtocol_
        )
    {
        _setFeeCollector(msg.sender);
        (wstEthOracleMiddleware_, liquidationRewardsManager_, usdn_, wusdn_) = _deployAndSetPeriferalContracts();

        // core contracts
        (rebalancer_, usdnProtocol_, usdn_, wusdn_) =
            _deployProtocol(liquidationRewardsManager_, wstEthOracleMiddleware_, WSTETH);

        // post-deployment tasks
        rebalancer_ = _setRebalancerAndHandleUsdnRoles(usdnProtocol_, usdn_);
        _initializeProtocol(usdnProtocol_, wstEthOracleMiddleware_);

        return (wstEthOracleMiddleware_, liquidationRewardsManager_, rebalancer_, usdn_, wusdn_, usdnProtocol_);
    }

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

    /**
     * @notice Handle post-deployment tasks
     * @param usdnProtocol The USDN protocol
     * @return rebalancer_ The rebalancer
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

    function _deployAndSetPeriferalContracts()
        internal
        returns (
            WstEthOracleMiddleware wstEthOracleMiddleware_,
            LiquidationRewardsManager liquidationRewardsManager_,
            Usdn usdn_,
            Wusdn wusdn_
        )
    {
        vm.startBroadcast();
        liquidationRewardsManager_ = new LiquidationRewardsManager(WSTETH);
        wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
            PYTH_ADDRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WSTETH), CHAINLINK_PRICE_VALIDITY
        );
        usdn_ = new Usdn(address(0), address(0));
        wusdn_ = new Wusdn(usdn_);
        vm.stopBroadcast();

        _setPeriferalContracts(wstEthOracleMiddleware_, liquidationRewardsManager_, usdn_);
    }
}
