// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SignedMath } from "../../../../src/libraries/SignedMath.sol";

/**
 * @title SignedMathHandler
 * @dev Wrapper to get gas usage report and coverage report
 */
contract SignedMathHandler {
    function safeAdd(int256 lhs, int256 rhs) external pure returns (int256) {
        return SignedMath.safeAdd(lhs, rhs);
    }

    function safeSub(int256 lhs, int256 rhs) external pure returns (int256) {
        return SignedMath.safeSub(lhs, rhs);
    }

    function safeMul(int256 lhs, int256 rhs) external pure returns (int256) {
        return SignedMath.safeMul(lhs, rhs);
    }

    function safeDiv(int256 lhs, int256 rhs) external pure returns (int256) {
        return SignedMath.safeDiv(lhs, rhs);
    }
}
