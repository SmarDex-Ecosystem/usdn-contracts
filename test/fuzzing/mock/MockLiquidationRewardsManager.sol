// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { LiquidationRewardsManager } from "../../../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";

/**
 * @title Contract to change liquidator rewards by setting a mocked gas price
 * @notice This contract is used to calculate the rewards given on liquidation and manipulate the reported gas price
 */
contract MockLiquidationRewardsManager is LiquidationRewardsManager {
    /**
     * @param wstETH The address of the wstETH token
     * @param chainlinkElapsedTimeLimit The duration after which the Chainlink gas price is considered stale
     */
    constructor(IWstETH wstETH, uint256 chainlinkElapsedTimeLimit)
        LiquidationRewardsManager(address(0), wstETH, chainlinkElapsedTimeLimit)
    { }

    function _getGasPrice(RewardsParameters memory) internal view override returns (uint256 gasPrice_) {
        gasPrice_ = tx.gasprice;
    }
}
