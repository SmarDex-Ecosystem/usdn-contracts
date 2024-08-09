// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IWstETH } from "../../interfaces/IWstETH.sol";
import { ChainlinkPriceInfo } from "../../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { LiquidationRewardsManager } from "../LiquidationRewardsManager.sol";
import { ChainlinkOracle } from "../oracles/ChainlinkOracle.sol";

/**
 * @title Contract to change liquidator rewards by setting a mocked gas price
 * @notice This contract is used to calculate the rewards given on liquidation and manipulate the reported gas price
 */
contract MockLiquidationRewardsManager is LiquidationRewardsManager {
    /**
     * @notice Mocked gas price
     * @dev This price will be used if greater than zero
     */
    int256 _mockedGasPrice;

    /**
     * @param chainlinkGasPriceFeed The address of the Chainlink gas price feed
     * @param wstETH The address of the wstETH token
     * @param chainlinkElapsedTimeLimit The duration after which the Chainlink gas price is considered stale
     */
    constructor(address chainlinkGasPriceFeed, IWstETH wstETH, uint256 chainlinkElapsedTimeLimit)
        LiquidationRewardsManager(chainlinkGasPriceFeed, wstETH, chainlinkElapsedTimeLimit)
    { }

    /**
     * @inheritdoc ChainlinkOracle
     * @notice Return the gas price from chainlink or the mocked gas price if set
     * @return price_ Price information from the chainlink oracle
     */
    function _getChainlinkLatestPrice() internal view override returns (ChainlinkPriceInfo memory price_) {
        price_ = super._getChainlinkLatestPrice();

        if (_mockedGasPrice > 0) {
            price_.price = _mockedGasPrice;
        }
    }

    /**
     * @notice Set a new mocked gas price
     * @param newMockedGasPrice The new gas price
     */
    function setMockedGasPrice(int256 newMockedGasPrice) external {
        _mockedGasPrice = newMockedGasPrice;
    }

    /**
     * @notice Get the current mocked gas price
     * @return price_ The mocked gas price
     */
    function getMockedGasPrice() external view returns (int256 price_) {
        price_ = _mockedGasPrice;
    }
}
