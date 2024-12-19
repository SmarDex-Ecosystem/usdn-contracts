// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IRebaseCallback {
    /**
     * @notice Called by the USDN token after a rebase has happened.
     * @param oldDivisor The value of the divisor before the rebase.
     * @param newDivisor The value of the divisor after the rebase (necessarily smaller than `oldDivisor`).
     * @return result_ Arbitrary data that will be forwarded to the caller of `rebase`.
     */
    function rebaseCallback(uint256 oldDivisor, uint256 newDivisor) external returns (bytes memory result_);
}
