// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IBaseLiquidationRewardsManager } from "../LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../OracleMiddleware/IBaseOracleMiddleware.sol";
import { IUsdn } from "../Usdn/IUsdn.sol";
import { IUsdnProtocolActions } from "./IUsdnProtocolActions.sol";
import { IUsdnProtocolCore } from "./IUsdnProtocolCore.sol";
import { IUsdnProtocolFallback } from "./IUsdnProtocolFallback.sol";
import { IUsdnProtocolLong } from "./IUsdnProtocolLong.sol";
import { IUsdnProtocolStorage } from "./IUsdnProtocolStorage.sol";
import { IUsdnProtocolVault } from "./IUsdnProtocolVault.sol";

/**
 * @title IUsdnProtocolImpl
 * @notice Interface for the implementation of the USDN protocol (completed with {IUsdnProtocolFallback})
 */
interface IUsdnProtocolImpl is
    IUsdnProtocolStorage,
    IUsdnProtocolActions,
    IUsdnProtocolVault,
    IUsdnProtocolLong,
    IUsdnProtocolCore
{
    /**
     * @notice Function to initialize the protocol storage
     * @dev This function should be called on deployment when creating the proxy
     * It can only be called once
     * @param usdn The USDN ERC20 contract
     * @param sdex The SDEX ERC20 contract
     * @param asset The asset ERC20 contract
     * @param oracleMiddleware The oracle middleware contract
     * @param liquidationRewardsManager The liquidation rewards manager contract
     * @param tickSpacing The positions tick spacing
     * @param feeCollector The address of the fee collector
     * @param managers The protocol managers
     * @param protocolFallback The protocol fallback contract
     * @param eip712Version The protocol eip712 version
     */
    function initializeStorage(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Managers memory managers,
        IUsdnProtocolFallback protocolFallback,
        string memory eip712Version
    ) external;
}
