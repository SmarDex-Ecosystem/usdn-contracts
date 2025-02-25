// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { DeployProtocolProd } from "./00_DeployProtocolProd.s.sol";

import { LiquidationRewardsManager } from "../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { Wusdn } from "../src/Usdn/Wusdn.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

contract DeployUsdnWsteth is DeployProtocolProd {
    address constant CHAINLINK_ETH_PRICE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant PYTH_ADRESS = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    bytes32 constant PYTH_ETH_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    IWstETH constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    uint256 constant CHAINLINK_GAS_PRICE_VALIDITY = 2 hours + 5 minutes;
    uint256 constant CHAINLINK_PRICE_VALIDITY = 1 hours + 2 minutes;
    Usdn constant USDN = Usdn(0xde17a000BA631c5d7c2Bd9FB692EFeA52D90DEE2);
    Wusdn constant WUSDN = Wusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);

    /**
     * @notice Deploy the USDN ecosystem with the WstETH as underlying
     * @return WstETH_ The WstETH contract
     * @return WstEthOracleMiddleware_ The WstETH oracle middleware
     * @return LiquidationRewardsManager_ The liquidation rewards manager
     * @return Rebalancer_ The rebalancer
     * @return Usdn_ The USDN contract
     * @return Wusdn_ The WUSDN contract
     * @return UsdnProtocol_ The USDN protocol
     */
    function run()
        internal
        returns (
            IERC20Metadata WstETH_,
            WstEthOracleMiddleware WstEthOracleMiddleware_,
            LiquidationRewardsManager LiquidationRewardsManager_,
            Rebalancer Rebalancer_,
            Usdn Usdn_,
            Wusdn Wusdn_,
            IUsdnProtocol UsdnProtocol_
        )
    {
        LiquidationRewardsManager_ = _deployLiquidationRewardsManager();
        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware();

        (Rebalancer_, UsdnProtocol_) = _deploy(LiquidationRewardsManager_, WstEthOracleMiddleware_, WSTETH, USDN);

        return (WSTETH, WstEthOracleMiddleware_, LiquidationRewardsManager_, Rebalancer_, USDN, WUSDN, UsdnProtocol_);
    }

    /**
     * @notice Deploy the liquidation rewards manager
     * @return liquidationRewardsManager_ The deployed contract
     */
    function _deployLiquidationRewardsManager()
        internal
        returns (LiquidationRewardsManager liquidationRewardsManager_)
    {
        liquidationRewardsManager_ = new LiquidationRewardsManager(WSTETH);
    }

    /**
     * @notice Deploy the WstETH oracle middleware
     * @return wstEthOracleMiddleware_ The deployed contract
     */
    function _deployWstEthOracleMiddleware() internal returns (WstEthOracleMiddleware wstEthOracleMiddleware_) {
        wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
            PYTH_ADRESS, PYTH_ETH_FEED_ID, CHAINLINK_ETH_PRICE, address(WSTETH), CHAINLINK_PRICE_VALIDITY
        );
    }
}
