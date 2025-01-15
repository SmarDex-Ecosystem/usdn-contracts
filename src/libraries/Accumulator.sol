// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

/**
 * @notice Library to operate on the liquidation multiplier accumulator values (512-bit integers).
 * @dev This is a wrapper for `HugeUint` that is deployed to its own address and called via `delegatecall`.
 */
library Accumulator {
    /**
     * @notice Calculates the sum `a + b` of two 512-bit unsigned integers.
     * @param a The first operand.
     * @param b The second operand.
     * @return res_ The sum of `a` and `b`.
     */
    function add(HugeUint.Uint512 memory a, HugeUint.Uint512 memory b)
        external
        pure
        returns (HugeUint.Uint512 memory res_)
    {
        res_ = HugeUint.add(a, b);
    }

    /**
     * @notice Calculates the difference `a - b` of two 512-bit unsigned integers.
     * @param a The first operand.
     * @param b The second operand.
     * @return res_ The difference `a - b`.
     */
    function sub(HugeUint.Uint512 memory a, HugeUint.Uint512 memory b)
        external
        pure
        returns (HugeUint.Uint512 memory res_)
    {
        res_ = HugeUint.sub(a, b);
    }

    /**
     * @notice Calculates the product `a * b` of two 256-bit unsigned integers using the Chinese remainder theorem.
     * @param a The first operand.
     * @param b The second operand.
     * @return res_ The product `a * b` of the operands as an unsigned 512-bit integer.
     */
    function mul(uint256 a, uint256 b) external pure returns (HugeUint.Uint512 memory res_) {
        res_ = HugeUint.mul(a, b);
    }

    /**
     * @notice Calculates the product `a * b` of a 512-bit unsigned integer and a 256-bit unsigned integer.
     * @param a The first operand.
     * @param b The second operand.
     * @return res_ The product `a * b` of the operands as an unsigned 512-bit integer.
     */
    function mul(HugeUint.Uint512 memory a, uint256 b) external pure returns (HugeUint.Uint512 memory res_) {
        res_ = HugeUint.mul(a, b);
    }

    /**
     * @notice Calculates the division `floor(a / b)` of a 512-bit unsigned integer by an unsigned 256-bit integer.
     * @param a The numerator as a 512-bit unsigned integer.
     * @param b The denominator as a 256-bit unsigned integer.
     * @return res_ The division `floor(a / b)` of the operands as an unsigned 256-bit integer.
     */
    function div(HugeUint.Uint512 memory a, uint256 b) external pure returns (uint256 res_) {
        res_ = HugeUint.div(a, b);
    }

    /**
     * @notice Computes the division floor(a/b) of two 512-bit integers, knowing the result fits inside a uint256.
     * @param a The numerator as a 512-bit integer.
     * @param b The denominator as a 512-bit integer.
     * @return res_ The quotient floor(a/b).
     */
    function div(HugeUint.Uint512 memory a, HugeUint.Uint512 memory b) external pure returns (uint256 res_) {
        res_ = HugeUint.div(a, b);
    }
}
