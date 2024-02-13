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
    /* -------------------------------------------------------------------------- */
    /*                                    Structs                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Parameters for the rewards calculation.
     * @param gasUsedPerTick Gas used per tick to liquidate.
     * @param otherGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplier Multiplier for the liquidators.
     */
    struct RewardsParameters {
        uint32 gasUsedPerTick;
        uint32 otherGasUsed;
        uint64 gasPriceLimit;
        uint16 multiplier; // to be divided by REWARD_MULTIPLIER_DENOMINATOR
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when the rewards parameters are changed.
     * @param gasUsedPerTick Gas used per tick to liquidate.
     * @param baseGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplier Multiplier for the liquidators.
     */
    event UpdateRewardsParameters(uint32 gasUsedPerTick, uint32 baseGasUsed, uint64 gasPriceLimit, uint16 multiplier);

    /* -------------------------------------------------------------------------- */
    /*                                   Errors                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerGasUsedPerTickTooHigh(uint256 value);
    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerBaseGasUsedTooHigh(uint256 value);
    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerGasPriceLimitTooHigh(uint256 value);
    /// @dev Indicates that one of the rewards parameter has been set to a value we consider too high.
    error LiquidationRewardsManagerMultiplierTooHigh(uint256 value);

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Denominator for the reward multiplier, will give us a 0.1% precision.
    uint16 public constant REWARD_MULTIPLIER_DENOMINATOR = 1000;
    /// @notice Number of decimals on the gas price, denominated in GWEI (9 decimals).
    uint8 public constant GAS_PRICE_DECIMALS = 9;
    /// @notice Fixed amount of gas a transaction consume.
    uint16 public constant BASE_GAS_COST = 21_000;

    /* -------------------------------------------------------------------------- */
    /*                              Storage Variables                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Address of the wstETH contract.
    IWstETH private immutable _wstEth;

    /// @notice Parameters for the rewards calculation
    /// @dev Those values need to be updated if the gas cost changes.
    RewardsParameters private _rewardsParameters;

    constructor(address chainlinkGasPriceFeed, IWstETH wstETH, uint256 chainlinkElapsedTimeLimit)
        Ownable(msg.sender)
        ChainlinkOracle(chainlinkGasPriceFeed, chainlinkElapsedTimeLimit)
    {
        _wstEth = wstETH;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 27_671,
            otherGasUsed: 29_681,
            gasPriceLimit: uint64(1000 * (10 ** GAS_PRICE_DECIMALS)),
            multiplier: 2000
        });
    }

    /**
     * @notice Get the gas price from Chainlink or tx.gasprice, the lesser of the 2 values.
     * @dev This function cannot return a value higher than the _gasPriceLimit storage variable.
     * @return _gasPrice The gas price.
     */
    function _getGasPrice(RewardsParameters memory rewardsParameters) private view returns (uint256 _gasPrice) {
        _gasPrice = (getChainlinkPrice()).price;

        if (tx.gasprice < _gasPrice) {
            _gasPrice = tx.gasprice;
        }

        // Avoid paying an insane amount if network is abnormally congested
        if (_gasPrice > rewardsParameters.gasPriceLimit) {
            _gasPrice = rewardsParameters.gasPriceLimit;
        }
    }

    /// @inheritdoc ILiquidationRewardsManager
    function getLiquidationRewards(uint16 tickAmount) external view returns (uint256 _wstETHRewards) {
        // Do not give rewards if no ticks were liquidated.
        if (tickAmount == 0) {
            return 0;
        }

        RewardsParameters memory rewardsParameters = _rewardsParameters;
        // Calculate te amount of gas spent during the liquidation.
        uint256 gasUsed =
            rewardsParameters.otherGasUsed + BASE_GAS_COST + (rewardsParameters.gasUsedPerTick * tickAmount);
        // Multiply by the gas price and the rewards multiplier.
        _wstETHRewards = _wstEth.getWstETHByStETH(
            gasUsed * _getGasPrice(rewardsParameters) * rewardsParameters.multiplier / REWARD_MULTIPLIER_DENOMINATOR
        );
    }

    /// @notice Returns the parameters used to calculate the rewards for a liquidation.
    function getRewardsParameters() external view returns (RewardsParameters memory) {
        return _rewardsParameters;
    }

    /**
     * @notice Set new parameters for the rewards calculation.
     * @param gasUsedPerTick Gas used per tick to liquidate.
     * @param baseGasUsed Gas used for the rest of the computation.
     * @param gasPriceLimit Upper limit for the gas price.
     * @param multiplier Multiplier for the liquidators.
     */
    function setRewardsParameters(uint32 gasUsedPerTick, uint32 baseGasUsed, uint64 gasPriceLimit, uint16 multiplier)
        external
        onlyOwner
    {
        if (gasUsedPerTick > 100_000) {
            revert LiquidationRewardsManagerGasUsedPerTickTooHigh(gasUsedPerTick);
        } else if (baseGasUsed > 200_000) {
            revert LiquidationRewardsManagerBaseGasUsedTooHigh(baseGasUsed);
        } else if (gasPriceLimit > (8000 * (10 ** GAS_PRICE_DECIMALS))) {
            revert LiquidationRewardsManagerGasPriceLimitTooHigh(gasPriceLimit);
        } else if (multiplier > 10) {
            revert LiquidationRewardsManagerMultiplierTooHigh(multiplier);
        }

        _rewardsParameters = RewardsParameters(gasUsedPerTick, baseGasUsed, gasPriceLimit, multiplier);

        emit UpdateRewardsParameters(gasUsedPerTick, baseGasUsed, gasPriceLimit, multiplier);
    }
}
