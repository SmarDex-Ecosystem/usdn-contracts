// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { ChainlinkOracle } from "../OracleMiddleware/oracles/ChainlinkOracle.sol";
import { IWstETH } from "../interfaces/IWstETH.sol";
import { IBaseLiquidationRewardsManager } from
    "../interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManager } from "../interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";
import { ChainlinkPriceInfo } from "../interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title LiquidationRewardsManager contract
 * @notice This contract is used by the USDN protocol to calculate the rewards that need to be paid out to the
 * liquidators
 * @dev This contract is a middleware between the USDN protocol and the gas price oracle
 */
contract LiquidationRewardsManager is ILiquidationRewardsManager, ChainlinkOracle, Ownable2Step {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ILiquidationRewardsManager
    uint32 public constant BPS_DIVISOR = 10_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant BASE_GAS_COST = 21_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_GAS_USED_PER_TICK = 500_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_OTHER_GAS_USED = 1_000_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_REBASE_GAS_USED = 200_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_REBALANCER_GAS_USED = 300_000;

    /// @inheritdoc ILiquidationRewardsManager
    uint256 public constant MAX_GAS_PRICE_LIMIT = 8000 gwei;

    /* -------------------------------------------------------------------------- */
    /*                              Storage Variables                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Address of the wstETH contract
    IWstETH private immutable _wstEth;

    /**
     * @notice Parameters for the rewards calculation
     * @dev Those values need to be updated if the gas cost changes
     */
    RewardsParameters private _rewardsParameters;

    /**
     * @param chainlinkGasPriceFeed The address of the Chainlink gas price feed
     * @param wstETH The address of the wstETH token
     * @param chainlinkTimeElapsedLimit Time after which the price feed data is considered stale
     */
    constructor(address chainlinkGasPriceFeed, IWstETH wstETH, uint256 chainlinkTimeElapsedLimit)
        Ownable(msg.sender)
        ChainlinkOracle(chainlinkGasPriceFeed, chainlinkTimeElapsedLimit)
    {
        _wstEth = wstETH;
        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: 50_232,
            otherGasUsed: 427_876,
            rebaseGasUsed: 3447,
            rebalancerGasUsed: 242_020,
            gasPriceLimit: 1000 gwei,
            multiplierBps: 30_000
        });
    }

    /**
     * @inheritdoc IBaseLiquidationRewardsManager
     * @dev In the current implementation, the `int256 remainingCollateral`, `ProtocolAction action`,
     * `bytes calldata rebaseCallbackResult` and `bytes calldata priceData` parameters are not used
     */
    function getLiquidationRewards(
        Types.LiqTickInfo[] calldata liquidatedTicks,
        bool rebased,
        Types.RebalancerAction rebalancerAction,
        Types.ProtocolAction,
        bytes calldata,
        bytes calldata
    ) external view returns (uint256 wstETHRewards_) {
        // do not give rewards if no ticks were liquidated
        if (liquidatedTicks.length == 0) {
            return 0;
        }

        RewardsParameters memory rewardsParameters = _rewardsParameters;
        // calculate the amount of gas spent during the liquidation
        uint256 gasUsed = rewardsParameters.otherGasUsed + BASE_GAS_COST
            + (
                uint256(rewardsParameters.gasUsedPerTick) * liquidatedTicks.length * rewardsParameters.multiplierBps
                    / BPS_DIVISOR
            );

        if (rebased) {
            gasUsed += rewardsParameters.rebaseGasUsed;
        }
        if (uint8(rebalancerAction) > uint8(Types.RebalancerAction.NoCloseNoOpen)) {
            gasUsed += rewardsParameters.rebalancerGasUsed;
        }

        // multiply by the gas price and the rewards multiplier
        wstETHRewards_ = _wstEth.getWstETHByStETH(gasUsed * _getGasPrice(rewardsParameters));
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
        uint32 rebalancerGasUsed,
        uint64 gasPriceLimit,
        uint32 multiplierBps
    ) external onlyOwner {
        if (gasUsedPerTick > MAX_GAS_USED_PER_TICK) {
            revert LiquidationRewardsManagerGasUsedPerTickTooHigh(gasUsedPerTick);
        } else if (otherGasUsed > MAX_OTHER_GAS_USED) {
            revert LiquidationRewardsManagerOtherGasUsedTooHigh(otherGasUsed);
        } else if (rebaseGasUsed > MAX_REBASE_GAS_USED) {
            revert LiquidationRewardsManagerRebaseGasUsedTooHigh(rebaseGasUsed);
        } else if (rebalancerGasUsed > MAX_REBALANCER_GAS_USED) {
            revert LiquidationRewardsManagerRebalancerGasUsedTooHigh(rebalancerGasUsed);
        } else if (gasPriceLimit > MAX_GAS_PRICE_LIMIT) {
            revert LiquidationRewardsManagerGasPriceLimitTooHigh(gasPriceLimit);
        } else if (multiplierBps > 10 * BPS_DIVISOR) {
            revert LiquidationRewardsManagerMultiplierBpsTooHigh(multiplierBps);
        }

        _rewardsParameters = RewardsParameters({
            gasUsedPerTick: gasUsedPerTick,
            otherGasUsed: otherGasUsed,
            rebaseGasUsed: rebaseGasUsed,
            rebalancerGasUsed: rebalancerGasUsed,
            gasPriceLimit: gasPriceLimit,
            multiplierBps: multiplierBps
        });

        emit RewardsParametersUpdated(
            gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed, gasPriceLimit, multiplierBps
        );
    }

    /**
     * @notice Get the gas price from Chainlink or tx.gasprice, the lesser of the 2 values
     * @dev This function cannot return a value higher than the _gasPriceLimit storage variable
     * @param rewardsParameters The rewards parameters
     * @return gasPrice_ The gas price
     */
    function _getGasPrice(RewardsParameters memory rewardsParameters) internal view returns (uint256 gasPrice_) {
        ChainlinkPriceInfo memory priceInfo = _getChainlinkLatestPrice();

        // if the gas price is invalid, return 0 and do not distribute rewards
        if (priceInfo.price <= 0) {
            return 0;
        }

        // we can safely cast as rawGasPrice cannot be below 0
        gasPrice_ = uint256(priceInfo.price);
        if (tx.gasprice < gasPrice_) {
            gasPrice_ = tx.gasprice;
        }

        // avoid paying an insane amount if the network is abnormally congested
        if (gasPrice_ > rewardsParameters.gasPriceLimit) {
            gasPrice_ = rewardsParameters.gasPriceLimit;
        }
    }
}
