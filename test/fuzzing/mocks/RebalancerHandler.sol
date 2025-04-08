// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../../src/UsdnProtocol//libraries/UsdnProtocolConstantsLibrary.sol";
import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";

/**
 * @title RebalancerHandler
 * @dev Wrapper to aid in testing the rebalancer
 */
contract RebalancerHandler is Rebalancer, Test {
    constructor(IUsdnProtocol usdnProtocol) Rebalancer(usdnProtocol) { }

    function i_refundEther() external {
        return _refundEther();
    }

    /// @dev Verifies the EIP712 delegation signature
    function i_verifyInitiateCloseDelegation(
        uint88 amount,
        address to,
        uint256 userMinPrice,
        uint256 deadline,
        bytes calldata delegationData
    ) external returns (address depositOwner_) {
        depositOwner_ = _verifyInitiateCloseDelegation(amount, to, userMinPrice, deadline, delegationData);
    }

    function i_initiateClosePosition(
        InitiateCloseData memory data,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData,
        bytes calldata delegationData
    ) external returns (Types.LongActionOutcome outcome_) {
        return _initiateClosePosition(data, currentPriceData, previousActionsData, delegationData);
    }

    function getPositionMaxLeverage(uint256 seed) external view returns (uint256 maxLeverage) {
        uint256 protocolMaxLeverage = this.getPositionMaxLeverage();
        uint256 minLeverage = Constants.REBALANCER_MIN_LEVERAGE;

        if (minLeverage >= protocolMaxLeverage) {
            return minLeverage + 1;
        }

        maxLeverage = bound(seed, minLeverage + 1, protocolMaxLeverage);

        return maxLeverage;
    }

    function getMinAssetDeposit(uint256 seed) external view returns (uint256 minAssetDeposit) {
        uint256 minLongPosition = _usdnProtocol.getMinLongPosition();
        uint256 maxBound = 100 ether;

        minAssetDeposit = bound(seed, minLongPosition, maxBound);

        return minAssetDeposit;
    }

    function getTimeLimits(uint256 seed)
        external
        pure
        returns (uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay)
    {
        uint64 seed1 = uint64(seed);
        uint64 seed2 = uint64(seed >> 64);
        uint64 seed3 = uint64(seed >> 128);
        uint64 seed4 = uint64(seed >> 192);

        validationDelay = uint64(bound(seed1, 1 minutes, 1 hours));
        validationDeadline = uint64(bound(seed2, validationDelay + 1 minutes, validationDelay + 24 hours));
        actionCooldown = uint64(bound(seed3, validationDeadline, MAX_ACTION_COOLDOWN));
        closeDelay = uint64(bound(seed4, 0, MAX_CLOSE_DELAY));

        return (validationDelay, validationDeadline, actionCooldown, closeDelay);
    }
}
