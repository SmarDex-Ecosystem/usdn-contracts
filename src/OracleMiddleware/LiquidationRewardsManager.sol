// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { ChainlinkPriceInfo } from "src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
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
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Denominator for the reward multiplier, will give us a 0.01% basis point.
    uint32 public constant REWARDS_MULTIPLIER_DENOMINATOR = 10_000;
    /// @notice Fixed amount of gas a transaction consume.
    /// @dev Is a uint256 to avoid overflows during gas usage calculations.
    uint256 public constant BASE_GAS_COST = 21_000;

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
            gasUsedPerTick: 32_043,
            otherGasUsed: 43_251,
            gasPriceLimit: uint64(1000 gwei),
            multiplierBps: 20_000
        });
    }

    /**
     * @inheritdoc ILiquidationRewardsManager
     * @dev In the current implementation, the `int256 amountLiquidated` parameter is not used
     */
    function getLiquidationRewards(uint16 tickAmount, int256) external view returns (uint256 wstETHRewards_) {
        // Do not give rewards if no ticks were liquidated.
        if (tickAmount == 0) {
            return 0;
        }

        RewardsParameters memory rewardsParameters = _rewardsParameters;
        // Calculate the amount of gas spent during the liquidation.
        uint256 gasUsed =
            rewardsParameters.otherGasUsed + BASE_GAS_COST + (rewardsParameters.gasUsedPerTick * tickAmount);
        // Multiply by the gas price and the rewards multiplier.
        wstETHRewards_ = _wstEth.getWstETHByStETH(
            gasUsed * _getGasPrice(rewardsParameters) * rewardsParameters.multiplierBps / REWARDS_MULTIPLIER_DENOMINATOR
        );
    }

    /// @inheritdoc ILiquidationRewardsManager
    function getRewardsParameters() external view returns (RewardsParameters memory) {
        return _rewardsParameters;
    }

    /// @inheritdoc ILiquidationRewardsManager
    function setRewardsParameters(
        uint32 gasUsedPerTick,
        uint32 otherGasUsed,
        uint64 gasPriceLimit,
        uint32 multiplierBps
    ) external onlyOwner {
        if (gasUsedPerTick > 500_000) {
            revert LiquidationRewardsManagerGasUsedPerTickTooHigh(gasUsedPerTick);
        } else if (otherGasUsed > 1_000_000) {
            revert LiquidationRewardsManagerOtherGasUsedTooHigh(otherGasUsed);
        } else if (gasPriceLimit > 8000 gwei) {
            revert LiquidationRewardsManagerGasPriceLimitTooHigh(gasPriceLimit);
        } else if (multiplierBps > 10 * REWARDS_MULTIPLIER_DENOMINATOR) {
            revert LiquidationRewardsManagerMultiplierBpsTooHigh(multiplierBps);
        }

        _rewardsParameters = RewardsParameters(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplierBps);

        emit RewardsParametersUpdated(gasUsedPerTick, otherGasUsed, gasPriceLimit, multiplierBps);
    }

    /**
     * @notice Get the gas price from Chainlink or tx.gasprice, the lesser of the 2 values.
     * @dev This function cannot return a value higher than the _gasPriceLimit storage variable.
     * @return gasPrice_ The gas price.
     */
    function _getGasPrice(RewardsParameters memory rewardsParameters) private view returns (uint256 gasPrice_) {
        ChainlinkPriceInfo memory priceInfo = getChainlinkPrice();

        // If the gas price is invalid, return 0 and do not distribute rewards.
        if (priceInfo.price <= 0) {
            return 0;
        }

        // We can safely cast as rawGasPrice cannot be below 0
        gasPrice_ = uint256(priceInfo.price);
        if (tx.gasprice < gasPrice_) {
            gasPrice_ = tx.gasprice;
        }

        // Avoid paying an insane amount if network is abnormally congested
        if (gasPrice_ > rewardsParameters.gasPriceLimit) {
            gasPrice_ = rewardsParameters.gasPriceLimit;
        }
    }
}
