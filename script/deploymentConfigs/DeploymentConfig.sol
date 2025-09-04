// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Sdex } from "../../test/utils/Sdex.sol";

import { ILiquidationRewardsManager } from
    "../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { IOracleMiddlewareWithPyth } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareWithPyth.sol";
import { IUsdn } from "../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolFallback } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @notice Base configuration contract for protocol deployment.
abstract contract DeploymentConfig {
    IERC20Metadata immutable UNDERLYING_ASSET;
    Sdex immutable SDEX;
    uint256 immutable INITIAL_LONG_AMOUNT;
    address immutable SENDER;

    Types.InitStorage initStorage;

    /**
     * @notice Set the protocol's peripheral contracts in the initialization struct.
     * @param oracleMiddleware The oracle middleware contract.
     * @param liquidationRewardsManager The liquidation reward manager contract.
     * @param usdn The USDN token contract.
     */
    function _setPeripheralContracts(
        IOracleMiddlewareWithPyth oracleMiddleware,
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
