// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IWstETH } from "../../../../src/interfaces/IWstETH.sol";
import { LiquidationRewardsManager } from "../../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";

/**
 * @title LiquidationRewardsManagerHandler
 * @dev Wrapper to aid in testing the LiquidationRewardsManager
 */
contract LiquidationRewardsManagerHandler is LiquidationRewardsManager, Test {
    constructor(IWstETH wstETH) LiquidationRewardsManager(wstETH) { }

    function getRewardsParameters(uint256 seed)
        external
        pure
        returns (
            uint32 gasUsedPerTick,
            uint32 otherGasUsed,
            uint32 rebaseGasUsed,
            uint32 rebalancerGasUsed,
            uint64 baseFeeOffset,
            uint16 gasMultiplierBps,
            uint16 positionBonusMultiplierBps,
            uint128 fixedReward,
            uint128 maxReward
        )
    {
        (gasUsedPerTick, otherGasUsed, rebaseGasUsed, rebalancerGasUsed) = _getGasParameters(seed);

        (baseFeeOffset, gasMultiplierBps, positionBonusMultiplierBps, fixedReward, maxReward) =
            _getRewardParameters(seed >> 128, fixedReward);
    }

    function _getGasParameters(uint256 seed)
        internal
        pure
        returns (uint32 gasUsedPerTick, uint32 otherGasUsed, uint32 rebaseGasUsed, uint32 rebalancerGasUsed)
    {
        uint32 seed1 = uint32(seed);
        uint32 seed2 = uint32(seed >> 32);
        uint32 seed3 = uint32(seed >> 64);
        uint32 seed4 = uint32(seed >> 96);

        gasUsedPerTick = uint32(bound(seed1, 0, MAX_GAS_USED_PER_TICK));
        otherGasUsed = uint32(bound(seed2, 0, MAX_OTHER_GAS_USED));
        rebaseGasUsed = uint32(bound(seed3, 0, MAX_REBASE_GAS_USED));
        rebalancerGasUsed = uint32(bound(seed4, 0, MAX_REBALANCER_GAS_USED));
    }

    function _getRewardParameters(uint256 seed, uint128 _fixedReward)
        internal
        pure
        returns (
            uint64 baseFeeOffset,
            uint16 gasMultiplierBps,
            uint16 positionBonusMultiplierBps,
            uint128 fixedReward,
            uint128 maxReward
        )
    {
        uint64 seed5 = uint64(seed);
        uint16 seed6 = uint16(seed >> 64);
        uint16 seed7 = uint16(seed >> 80);
        uint128 seed8 = uint128(seed >> 96);

        baseFeeOffset = uint64(bound(seed5, 0, 1000 gwei));
        gasMultiplierBps = uint16(bound(seed6, 0, 10_000));
        positionBonusMultiplierBps = uint16(bound(seed7, 0, 10_000));

        fixedReward = uint128(bound(seed8 % 1000, 0, 10 ether));
        maxReward = uint128(bound((seed8 / 1000) % 1000, _fixedReward, 100 ether));
    }
}
