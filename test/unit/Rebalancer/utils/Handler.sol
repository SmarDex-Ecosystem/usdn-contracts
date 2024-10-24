// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Rebalancer } from "../../../../src/Rebalancer/Rebalancer.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title RebalancerHandler
 * @dev Wrapper to aid in testing the rebalancer
 */
contract RebalancerHandler is Rebalancer, Test {
    constructor(IUsdnProtocol usdnProtocol, string memory eip712Version) Rebalancer(usdnProtocol, eip712Version) { }

    /// @dev Sets the position version to the current one + 1
    function incrementPositionVersion() external {
        ++_positionVersion;
    }

    /**
     * @dev Sets the _lastLiquidatedVersion to the provided value
     * @param version The version to set
     */
    function setLastLiquidatedVersion(uint128 version) external {
        _lastLiquidatedVersion = version;
    }

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
}
