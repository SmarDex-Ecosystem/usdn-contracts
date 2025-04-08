// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";

/**
 * @title IRebalancerHandler
 * @dev Interface for RebalancerHandler for testing purposes
 */
interface IRebalancerHandler {
    /**
     * @dev Refunds any ETH sent to the contract
     */
    function i_refundEther() external;

    /**
     * @dev Verifies the EIP712 delegation signature
     * @param amount Amount to close
     * @param to Recipient of the closed position
     * @param userMinPrice Minimum price acceptable to the user
     * @param deadline Deadline for the signature validity
     * @param delegationData Signature data
     * @return depositOwner_ Address of the deposit owner
     */
    function i_verifyInitiateCloseDelegation(
        uint88 amount,
        address to,
        uint256 userMinPrice,
        uint256 deadline,
        bytes calldata delegationData
    ) external returns (address depositOwner_);

    /**
     * @dev Initiates closing a position
     * @param data Data for initiating position close
     * @param currentPriceData Current price data
     * @param previousActionsData Previous actions data
     * @param delegationData Delegation data
     * @return outcome_ Outcome of the action
     */
    function i_initiateClosePosition(
        Rebalancer.InitiateCloseData memory data,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData,
        bytes calldata delegationData
    ) external returns (Types.LongActionOutcome outcome_);

    /**
     * @dev Gets a valid position max leverage for testing
     * @param seed Random seed to generate the max leverage value
     * @return maxLeverage A valid max leverage value
     */
    function getPositionMaxLeverage(uint256 seed) external view returns (uint256 maxLeverage);

    /**
     * @dev Gets a valid minimum asset deposit value for testing
     * @param seed Random seed to generate the minimum asset deposit value
     * @return minAssetDeposit A valid minimum asset deposit value
     */
    function getMinAssetDeposit(uint256 seed) external view returns (uint256 minAssetDeposit);

    /**
     * @dev Gets valid time limits for testing
     * @param seed Random seed for data generation
     * @return validationDelay The validation delay
     * @return validationDeadline The validation deadline
     * @return actionCooldown The action cooldown period
     * @return closeDelay The close delay period
     */
    function getTimeLimits(uint256 seed)
        external
        pure
        returns (uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay);
}
