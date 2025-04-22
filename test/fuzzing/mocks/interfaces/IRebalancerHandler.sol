// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
     * @return maxLeverage A valid max leverage value
     */
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage);

    /**
     * @dev Gets a valid minimum long position value for testing
     * @return minLongPosition A valid minimum long position deposit value
     */
    function getMinLongAssetDeposit() external view returns (uint256 minLongPosition);
}
