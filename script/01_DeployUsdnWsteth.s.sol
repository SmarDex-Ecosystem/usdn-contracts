// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { DeployProtocolProd } from "./utils/DeployProtocolProd.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract DeployUsdnWsteth is DeployProtocolProd {
    address constant CHAINLINK_ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant PYTH_ADRESS = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 constant PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    IWstETH constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    uint256 constant CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    uint256 constant INITIAL_LONG_AMOUNT = 200 ether;

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
        // peripheral contracts
        vm.startBroadcast();
        liquidationRewardsManager_ = new LiquidationRewardsManager(WSTETH);
        wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
            PYTH_ADRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WSTETH), CHAINLINK_PRICE_VALIDITY
        );
        vm.stopBroadcast();

        // core contracts
        (rebalancer_, usdnProtocol_, usdn_, wusdn_) =
            _deployProtocol(liquidationRewardsManager_, wstEthOracleMiddleware_, WSTETH);

        // post-deployment tasks
        vm.startBroadcast();
        _handleRoles(usdnProtocol_, rebalancer_, usdn_);
        _initializeProtocol(usdnProtocol_, wstEthOracleMiddleware_);
        vm.stopBroadcast();

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
        (bool result,) = address(WSTETH).call{ value: ethAmount }(hex"");
        require(result, "Failed to mint wstETH");

        WSTETH.approve(address(usdnProtocol), depositAmount + INITIAL_LONG_AMOUNT);

        usdnProtocol.initialize(uint128(depositAmount), uint128(INITIAL_LONG_AMOUNT), desiredLiqPrice, "");
    }

    /**
     * @notice Handle post-deployment tasks
     * @param usdnProtocol The USDN protocol
     * @param rebalancer The rebalancer
     */
    function _handleRoles(IUsdnProtocol usdnProtocol, Rebalancer rebalancer, Usdn usdn) internal {
        bytes32 ADMIN_SET_EXTERNAL_ROLE = Constants.ADMIN_SET_EXTERNAL_ROLE;
        bytes32 SET_EXTERNAL_ROLE = Constants.SET_EXTERNAL_ROLE;

        usdnProtocol.grantRole(ADMIN_SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.setRebalancer(rebalancer);

        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
    }
}
