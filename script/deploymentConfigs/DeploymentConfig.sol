// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ILiquidationRewardsManager } from
    "../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IOracleMiddleware } from "../../src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolFallback } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Sdex } from "../../test/utils/Sdex.sol";

/// @notice Base configuration contract for protocol deployment.
abstract contract DeploymentConfig {
    IERC20Metadata immutable UNDERLYING_ASSET;
    Sdex immutable SDEX;
    uint256 immutable INITIAL_LONG_AMOUNT;

    Types.InitStorage initStorage;

    /**
     * @notice Set the protocol's peripheral contracts in the initialization struct.
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation reward manager contract.
     * @param usdn The USDN token contract.
     */
    function _setPeripheralContracts(
        IOracleMiddleware oracleMiddleware,
        ILiquidationRewardsManager liquidationRewardsManager,
        IUsdn usdn
    ) internal virtual;

    /**
     * @notice Set the protocol's fee collector in the initialization struct.
     * @param feeCollector The address of the fee collector.
     */
    function _setFeeCollector(address feeCollector) internal virtual;

    /**
     * @notice Set the protocol's fallback contract in the initialization struct.
     * @param protocolFallback The protocol fallback contract.
     */
    function _setProtocolFallback(IUsdnProtocolFallback protocolFallback) internal virtual;
}
