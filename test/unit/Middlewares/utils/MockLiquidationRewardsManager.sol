    // SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IWstETH } from "src/interfaces/IWstETH.sol";
import { ILiquidationRewardsManager } from "src/interfaces/OracleMiddleware/ILiquidationRewardsManager.sol";

/**
 * @title MockLiquidationRewardsManager contract
 * @notice This contract is used by the USDN protocol to calculate the rewards that need to be paid out to the
 * liquidators.
 * @dev This contract is a middleware between the USDN protocol and the gas price oracle.
 */
contract MockLiquidationRewardsManager is ILiquidationRewardsManager {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ILiquidationRewardsManager
    uint32 public constant REWARDS_MULTIPLIER_DENOMINATOR = 10_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant BASE_GAS_COST = 21_000;

    /* -------------------------------------------------------------------------- */
    /*                              Storage Variables                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Address of the wstETH contract.
    IWstETH private immutable _wstEth;

    /**
     * @notice Parameters for the rewards calculation.
     * @dev Those values need to be updated if the gas cost changes.
     */
    RewardsParameters private _rewardsParameters;

    constructor(address, IWstETH wstETH, uint256) {
        _wstEth = wstETH;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 31_974,
            otherGasUsed: 384_124,
            rebaseGasUsed: 8966,
            gasPriceLimit: 1000 gwei,
            multiplierBps: 20_000
        });
    }

    /**
     * @inheritdoc ILiquidationRewardsManager
     * @dev In the current implementation, the `int256 amountLiquidated` parameter is not used
     */
    function getLiquidationRewards(uint16 tickAmount, int256, bool rebased)
        external
        view
        returns (uint256 wstETHRewards_)
    {
        // Do not give rewards if no ticks were liquidated.
        if (tickAmount == 0) {
            return 0;
        }

        RewardsParameters memory rewardsParameters = _rewardsParameters;
        // Calculate the amount of gas spent during the liquidation.
        uint256 gasUsed =
            rewardsParameters.otherGasUsed + BASE_GAS_COST + (rewardsParameters.gasUsedPerTick * tickAmount);
        if (rebased) {
            gasUsed += rewardsParameters.rebaseGasUsed;
        }
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
        uint32 rebaseGasUsed,
        uint64 gasPriceLimit,
        uint32 multiplierBps
    ) external {
        if (gasUsedPerTick > 500_000) {
            revert LiquidationRewardsManagerGasUsedPerTickTooHigh(gasUsedPerTick);
        } else if (otherGasUsed > 1_000_000) {
            revert LiquidationRewardsManagerOtherGasUsedTooHigh(otherGasUsed);
        } else if (rebaseGasUsed > 200_000) {
            revert LiquidationRewardsManagerRebaseGasUsedTooHigh(rebaseGasUsed);
        } else if (gasPriceLimit > 8000 gwei) {
            revert LiquidationRewardsManagerGasPriceLimitTooHigh(gasPriceLimit);
        } else if (multiplierBps > 10 * REWARDS_MULTIPLIER_DENOMINATOR) {
            revert LiquidationRewardsManagerMultiplierBpsTooHigh(multiplierBps);
        }

        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: gasUsedPerTick,
            otherGasUsed: otherGasUsed,
            rebaseGasUsed: rebaseGasUsed,
            gasPriceLimit: gasPriceLimit,
            multiplierBps: multiplierBps
        });

        emit RewardsParametersUpdated(gasUsedPerTick, otherGasUsed, rebaseGasUsed, gasPriceLimit, multiplierBps);
    }

    /**
     * @notice Get the gas price from Chainlink or tx.gasprice, the lesser of the 2 values.
     * @dev This function cannot return a value higher than the _gasPriceLimit storage variable.
     * @return gasPrice_ The gas price.
     */
    function _getGasPrice(RewardsParameters memory) internal pure returns (uint256 gasPrice_) {
        return 20e9;
    }
}
