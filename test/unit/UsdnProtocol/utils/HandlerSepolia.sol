// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UsdnProtocolSepolia } from "../../../../src/UsdnProtocol/UsdnProtocolSepolia.sol";
import { IBaseOracleMiddleware } from "../../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { ILiquidationRewardsManager } from "../../../../src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolFallback } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";

/**
 * @title UsdnProtocolHandlerSepolia
 * @dev Wrapper to aid in testing the protocol on Sepolia
 */
contract UsdnProtocolHandlerSepolia is UsdnProtocolSepolia, Test {
    function initializeStorageHandler(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Managers memory managers,
        IUsdnProtocolFallback protocolFallback
    ) public initializer {
        initializeStorage(
            usdn,
            sdex,
            asset,
            oracleMiddleware,
            liquidationRewardsManager,
            tickSpacing,
            feeCollector,
            managers,
            protocolFallback
        );
    }

    /// @dev Useful to completely disable funding, which is normally initialized with a positive bias value
    function resetEMA() external {
        s._EMA = 0;
    }
}
