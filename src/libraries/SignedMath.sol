// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title SignedMath
 * @notice Perform signed math operations safely, reverting with a custom error in case of overflow.
 */
library SignedMath {
    /// @dev Indicates that the signed add operation overflowed.
    error SignedMathOverflowedAdd(int256 lhs, int256 rhs);

    /// @dev Indicates that the signed sub operation overflowed.
    error SignedMathOverflowedSub(int256 lhs, int256 rhs);

    /// @dev Indicates that the signed mul operation overflowed.
    error SignedMathOverflowedMul(int256 lhs, int256 rhs);

    /// @dev Indicates that the signed div operation overflowed.
    error SignedMathOverflowedDiv(int256 lhs, int256 rhs);

    /// @dev Indicates that a division by zero occurred.
    error SignedMathDivideByZero(int256 lhs);

    /**
     * @notice Safely add two signed integers, reverting on overflow.
     * @param lhs left hand side operand
     * @param rhs right hand side operand
     * @return res_ the result of lhs + rhs
     */
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

    /**
     * @notice Safely subtract two signed integers, reverting on overflow.
     * @param lhs left hand side operand
     * @param rhs right hand side operand
     * @return res_ the result of lhs - rhs
     */
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

    /**
     * @notice Safely multiply two signed integers, reverting on overflow.
     * @param lhs left hand side operand
     * @param rhs right hand side operand
     * @return res_ the result of lhs * rhs
     */
    function safeMul(int256 lhs, int256 rhs) internal pure returns (int256 res_) {
        unchecked {
            if (lhs == 0) {
                return 0;
            }
            res_ = lhs * rhs;
            // There is a special case where the first condition below does not catch the overflow: `lhs = -1` and
            // `rhs = type(int256).min`.
            // In such a case, `res_` overflows and is equal to `type(int256).min`. Then, `res_ / lhs` also overflows
            // and is equal to `type(int256).min`, so the condition does not catch it. We add an additional condition
            // for this specific case. This is not a problem when lhs and rhs are swapped, because
            // `res_ / type(int256).min` equals `1` which is not equal to `-1`.
            if (res_ / lhs != rhs || (rhs == type(int256).min && lhs == -1)) {
                revert SignedMathOverflowedMul(lhs, rhs);
            }
        }
    }

    /**
     * @notice Safely divide two signed integers, reverting on division by zero.
     * @param lhs left hand side operand
     * @param rhs right hand side operand
     * @return res_ the result of lhs / rhs
     */
    function safeDiv(int256 lhs, int256 rhs) internal pure returns (int256 res_) {
        unchecked {
            if (rhs == 0) {
                revert SignedMathDivideByZero(lhs);
            }
            // There is a special case where the division would overflow because
            // `abs(type(int256).min) > type(int256).max`. So if `lhs = type(int256).min` and `rhs = -1`, the result
            // would be `-type(int256).min` which does not fit in a `int256`. We add an additional condition for this
            // specific case.
            if (lhs == type(int256).min && rhs == -1) {
                revert SignedMathOverflowedDiv(lhs, rhs);
            }
            res_ = lhs / rhs;
        }
    }
}
