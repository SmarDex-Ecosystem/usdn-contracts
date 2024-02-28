// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ChainlinkPriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";

/**
 * @title Contract to change liquidator rewards by setting a mocked gas price.
 * @notice This contract is used to calculate the rewards given on liquidation and manipulate the reported gas price.
 */
contract MockLiquidationRewardsManager is LiquidationRewardsManager {
    /**
     * @notice Mocked gas price
     * @dev This price will be used if greater than zero.
     */
    int256 _mockedGasPrice;

    constructor(address chainlinkGasPriceFeed, IWstETH wstETH, uint256 chainlinkElapsedTimeLimit)
        LiquidationRewardsManager(chainlinkGasPriceFeed, wstETH, chainlinkElapsedTimeLimit)
    { }

    /**
     * @notice Return the gas price from chainlink or the mocked gas price if set.
     * @return price_ Price information from the chainlink oracle.
     */
    function _getChainlinkPrice() internal view override returns (ChainlinkPriceInfo memory price_) {
        price_ = super._getChainlinkPrice();

        if (_mockedGasPrice > 0) {
            price_.price = _mockedGasPrice;
        }
    }

    /// @notice Set a new mocked gas price.
    function setMockedGasPrice(int256 newMockedGasPrice) external {
        _mockedGasPrice = newMockedGasPrice;
    }

    /// @notice Get the current mocked gas price.
    function getMockedGasPrice() external view returns (int256) {
        return _mockedGasPrice;
    }
}
