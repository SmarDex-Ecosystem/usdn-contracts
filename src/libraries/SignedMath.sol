// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

library SignedMath {
    error SignedMathOverflowedAdd(int256 lhs, int256 rhs);

    error SignedMathOverflowedSub(int256 lhs, int256 rhs);

    error SignedMathOverflowedMul(int256 lhs, int256 rhs);

    error SignedMathDivideByZero(int256 lhs);

    function safeAdd(int256 lhs, int256 rhs) internal pure returns (int256 res_) {
        unchecked {
            res_ = lhs + rhs;
            if (lhs >= 0 && res_ < rhs) {
                revert SignedMathOverflowedAdd(lhs, rhs);
            }
            if (lhs < 0 && res_ > rhs) {
                revert SignedMathOverflowedAdd(lhs, rhs);
            }
        }
    }

    function safeSub(int256 lhs, int256 rhs) internal pure returns (int256 res_) {
        unchecked {
            res_ = lhs - rhs;
            if (rhs >= 0 && res_ > lhs) {
                revert SignedMathOverflowedSub(lhs, rhs);
            }
            if (rhs < 0 && res_ < lhs) {
                revert SignedMathOverflowedSub(lhs, rhs);
            }
        }
    }

    function safeMul(int256 lhs, int256 rhs) internal pure returns (int256 res_) {
        unchecked {
            if (lhs == 0) {
                return 0;
            }
            res_ = lhs * rhs;
            if (res_ / lhs != rhs) {
                revert SignedMathOverflowedMul(lhs, rhs);
            }
        }
    }

    function safeDiv(int256 lhs, int256 rhs) internal pure returns (int256 res_) {
        unchecked {
            if (rhs == 0) {
                revert SignedMathDivideByZero(lhs);
            }
            res_ = lhs / rhs;
        }
    }
}
