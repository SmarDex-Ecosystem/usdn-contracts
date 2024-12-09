// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
}
