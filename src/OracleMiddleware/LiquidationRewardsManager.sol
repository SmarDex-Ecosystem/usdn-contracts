// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { PriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { ChainlinkOracle } from "src/OracleMiddleware/oracles/ChainlinkOracle.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";

/**
 * @title LiquidationRewardsManager contract
 * @notice This contract is used by the USDN protocol to calculate the rewards that need to be payed out to the
 * liquidators.
 * @dev This contract is a middleware between the USDN protocol and the gas price oracle.
 */
contract LiquidationRewardsManager is ILiquidationRewardsManager, ChainlinkOracle, Ownable {
    uint8 private constant GAS_PRICE_DECIMALS = 9;
    uint8 public constant REWARD_MULTIPLIER_DENOMINATOR = 100;

    /// @notice Address of the wstETH contract.
    IWstETH private immutable _wstEth;

    /// @notice Gas used per tick to liquidate.
    uint256 private _gasUsedPerTick = 27_671;
    /// @notice Gas used for the rest of the computation.
    uint256 private _baseGasUsed = 25_481 + 21_000;
    /// @notice Upper limit for the gas price.
    uint256 private _gasPriceLimit = 1000 * (10 ** GAS_PRICE_DECIMALS);
    /// @notice Reward multiplier for the liquidators.
    uint16 private _rewardsMultiplier = 200; // to be divided by REWARD_MULTIPLIER_DENOMINATOR

    constructor(address chainlinkGasPriceFeed, IWstETH wstETHAddress, uint256 chainlinkElapsedTimeLimit)
        Ownable(msg.sender)
        ChainlinkOracle(chainlinkGasPriceFeed, chainlinkElapsedTimeLimit)
    {
        _wstEth = wstETHAddress;
    }

    /**
     * @notice Get the gas price from Chainlink or tx.gasprice, the lesser of the 2 values.
     * @dev This function cannot return a value higher than the _gasPriceLimit storage variable.
     * @return _gasPrice The gas price.
     */
    function getGasPrice() private view returns (uint256 _gasPrice) {
        _gasPrice = (getChainlinkPrice()).price;

        if (tx.gasprice < _gasPrice) {
            _gasPrice = tx.gasprice;
        }

        // Avoid paying an insane amount if network is abnormally congested
        if (_gasPrice > _gasPriceLimit) {
            _gasPrice = _gasPriceLimit;
        }
    }

    /// @inheritdoc ILiquidationRewardsManager
    function getLiquidationRewards(uint16 tickAmount) external view returns (uint256 _wstETHRewards) {
        uint256 gasUsed = _baseGasUsed + _gasUsedPerTick * tickAmount;
        _wstETHRewards =
            _wstEth.getWstETHByStETH(gasUsed * getGasPrice() * _rewardsMultiplier / REWARD_MULTIPLIER_DENOMINATOR);
    }

    /* -------------------------------------------------------------------------- */
    /*                          Storage Setters & Getters                         */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the amount of gas used per tick.
    function getGasUsedPerTick() external view returns (uint256) {
        return _gasUsedPerTick;
    }

    /**
     * @notice Set a new value for the gas usded per tick.
     * @param newGasUsedPerTick The new gas used per tick value.
     */
    function setGasUsedPerTick(uint256 newGasUsedPerTick) external onlyOwner {
        _gasUsedPerTick = newGasUsedPerTick;

        emit UpdateGasUsedPerTick(newGasUsedPerTick);
    }

    /// @notice Returns the amount of gas used by a liquidation transaction, minus the calculation per tick.
    function getBaseGasUsed() external view returns (uint256) {
        return _baseGasUsed;
    }

    /**
     * @notice Set a new value for the base gas used.
     * @param newBaseGasUsed The new base gas used value.
     */
    function setBaseGasUsed(uint256 newBaseGasUsed) external onlyOwner {
        _baseGasUsed = newBaseGasUsed;

        emit UpdateBaseGasUsed(newBaseGasUsed);
    }

    /// @notice Returns the gas price limit for the rewards calculation.
    function getGasPriceLimit() external view returns (uint256) {
        return _gasPriceLimit;
    }

    /**
     * @notice Set a new gas price limit.
     * @param newGasPriceLimit The new gas price limit value.
     */
    function setGasPriceLimit(uint256 newGasPriceLimit) external onlyOwner {
        _gasPriceLimit = newGasPriceLimit;

        emit UpdateGasPriceLimit(newGasPriceLimit);
    }

    /// @notice Returns the liquidator rewards multiplier.
    function getRewardsMultiplier() external view returns (uint16) {
        return _rewardsMultiplier;
    }

    /**
     * @notice Set a new rewards multiplier.
     * @param newRewardsMultiplier The new rewards multiplier value.
     */
    function setRewardsMultiplier(uint16 newRewardsMultiplier) external onlyOwner {
        _rewardsMultiplier = newRewardsMultiplier;

        emit UpdateRewardsMultiplier(newRewardsMultiplier);
    }
}
