// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @notice A library for manipulating uint512 quantities.
 * The huge ints are represented as two uint256 "limbs", a `lo` limb for the least-significant bits, and a `hi` limb
 * for the most significant bits. The result uint512 value is calculated as `hi * 2^256 + lo`.
 */
library HugeInt {
    /// @notice Indicates that the division failed because the divisor is zero or the result overflows a uint256.
    error HugeIntDivisionFailed();

    /**
     * @notice A 512-bit integer represented as two 256-bit limbs
     * @dev The integer value can be reconstructed as `hi * 2^256 + lo`
     * @param lo The least-significant bits (lower limb) of the integer
     * @param hi The most-significant bits (higher limb) of the integer
     */
    struct Uint512 {
        uint256 lo;
        uint256 hi;
    }

    /**
     * @notice Wrap a uint256 into a Uint512 integer
     * @param x A uint256 integer
     * @return The same value as a 512-bit integer
     */
    function wrap(uint256 x) internal pure returns (Uint512 memory) {
        return Uint512(x, 0);
    }

    /**
     * @notice Calculate the sum `a + b` of two 512-bit unsigned integers.
     * @dev The result is not checked for overflow, the caller must ensure that the result is less than 2^512.
     * @param a The first operand
     * @param b The second operand
     * @return res_ The sum of `a` and `b`
     */
    function add(Uint512 memory a, Uint512 memory b) external pure returns (Uint512 memory res_) {
        (res_.lo, res_.hi) = _add(a.lo, a.hi, b.lo, b.hi);
    }

    /**
     * @notice Calculate the difference `a - b` of two 512-bit unsigned integers.
     * @dev The result is not checked for underflow, the caller must ensure that the second operand is less than or
     * equal to the first operand.
     * @param a The first operand
     * @param b The second operand
     * @return res_ The difference `a - b`
     */
    function sub(Uint512 memory a, Uint512 memory b) external pure returns (Uint512 memory res_) {
        (uint256 a0, uint256 a1) = (a.lo, a.hi);
        (uint256 b0, uint256 b1) = (b.lo, b.hi);
        uint256 lo;
        uint256 hi;
        assembly {
            lo := sub(a0, b0)
            hi := sub(sub(a1, b1), lt(a0, b0))
        }
        return Uint512(lo, hi);
    }

    /**
     * @notice Calculate the product `a * b` of two 256-bit unsigned integers using the chinese remainder theorem.
     * @param a The first operand
     * @param b The second operand
     * @return res_ The product `a * b` of the operands as an unsigned 512-bit integer
     */
    function mul256(uint256 a, uint256 b) external pure returns (Uint512 memory res_) {
        (res_.lo, res_.hi) = _mul256(a, b);
    }

    /**
     * @notice Calculate the product `a * b` of two 512-bit unsigned integers
     * @dev Credits chfast (Apache 2.0 License): https://github.com/chfast/intx
     * This function does not check for overflows, the caller must ensure that the result fits inside a uint512.
     * @param a The first operand
     * @param b The second operand
     * @return res_ The product `a * b` of the operands as an unsigned 512-bit integer
     */
    function mul(Uint512 memory a, Uint512 memory b) external pure returns (Uint512 memory res_) {
        (res_.lo, res_.hi) = _mul256(a.lo, b.lo);
        unchecked {
            res_.hi += (a.lo * b.hi) + (a.hi * b.lo);
        }
    }

    /**
     * @notice Calculate the division `floor(a / b)` of a 512-bit unsigned integer by an unsigned 256-bit integer.
     * @dev The call will revert if the result doesn't fit inside a uint256 or if the denominator is zero.
     * @param a The numerator as a 512-bit unsigned integer
     * @param b The denominator as a 256-bit unsigned integer
     * @return res_ The division `floor(a / b)` of the operands as an unsigned 256-bit integer
     */
    function div256(Uint512 memory a, uint256 b) external pure returns (uint256 res_) {
        // make sure the output fits inside a uint256, also prevents b == 0
        if (b <= a.hi) {
            revert HugeIntDivisionFailed();
        }
        // if the numerator is smaller than the denominator, the result is zero
        if (a.hi == 0 && a.lo < b) {
            return 0;
        }
        // the first operand fits in 256 bits, we can use the Solidity division operator
        if (a.hi == 0) {
            unchecked {
                return a.lo / b;
            }
        }
        res_ = _div256(a.lo, a.hi, b);
    }

    /**
     * @notice Compute the division floor(a/b) of two 512-bit integers, knowing the result fits inside a uint256.
     * @dev Credits chfast (Apache 2.0 License): https://github.com/chfast/intx
     * @param a The numerator as a 512-bit integer
     * @param b The denominator as a 512-bit integer
     * @return res_ The quotient floor(a/b)
     */
    function div(Uint512 memory a, Uint512 memory b) external pure returns (uint256 res_) {
        // prevents b == 0
        if (b.hi == 0 && b.lo == 0) {
            revert HugeIntDivisionFailed();
        }
        // if both operands fit inside a uint256, we can use the Solidity division operator
        if (a.hi == 0 && b.hi == 0) {
            unchecked {
                return a.lo / b.lo;
            }
        }
        // if the numerator is smaller than the denominator, the result is zero
        if (a.hi < b.hi || (a.hi == b.hi && a.lo < b.lo)) {
            return 0;
        }
        // if the divisor and result fit inside a uint256, we can use the {div256} function
        if (b.hi == 0 && b.lo > a.hi) {
            return _div256(a.lo, a.hi, b.lo);
        }
        // Division algo
        (uint256 a0, uint256 a1) = (a.lo, a.hi);
        (uint256 b0, uint256 b1) = (b.lo, b.hi);

        uint256 lsh = _clz(b1);
        if (lsh == 0) {
            // numerator is equal or larger than the denominator, and denominator is at least 0b1000...
            // the result is necessarily 1
            return 1;
        }

        uint256 bn_lo;
        uint256 bn_hi;
        uint256 an_lo;
        uint256 an_hi;
        uint256 an_ex;
        assembly {
            let rsh := sub(256, lsh)
            bn_lo := shl(lsh, b0)
            bn_hi := or(shl(lsh, b1), shr(rsh, b0))
            an_lo := shl(lsh, a0)
            an_hi := or(shl(lsh, a1), shr(rsh, a0))
            an_ex := shr(rsh, a1)
        }
        uint256 v = _reciprocal_2(bn_lo, bn_hi);
        res_ = _div_2(an_lo, an_hi, an_ex, bn_lo, bn_hi, v);
    }

    /**
     * @notice Calculate the sum `a + b` of two 512-bit unsigned integers.
     * @dev Credits Remco Bloemen (MIT license): https://2π.com/17/512-bit-division/
     * The result is not checked for overflow, the caller must ensure that the result is less than 2^512.
     * @param a0 The low limb of the first operand
     * @param a1 The high limb of the first operand
     * @param b0 The low limb of the second operand
     * @param b1 The high limb of the second operand
     * @return lo_ The low limb of the result of `a + b`
     * @return hi_ The high limb of the result of `a + b`
     */
    function _add(uint256 a0, uint256 a1, uint256 b0, uint256 b1) internal pure returns (uint256 lo_, uint256 hi_) {
        assembly {
            lo_ := add(a0, b0)
            hi_ := add(add(a1, b1), lt(lo_, a0))
        }
    }

    /**
     * @notice Calculate the difference `a - b` of two 512-bit unsigned integers.
     * @dev Credits Remco Bloemen (MIT license): https://2π.com/17/512-bit-division/
     * The result is not checked for underflow, the caller must ensure that the second operand is less than or equal to
     * the first operand.
     * @param a0 The low limb of the first operand
     * @param a1 The high limb of the first operand
     * @param b0 The low limb of the second operand
     * @param b1 The high limb of the second operand
     * @return lo_ The low limb of the result of `a - b`
     * @return hi_ The high limb of the result of `a - b`
     */
    function _sub(uint256 a0, uint256 a1, uint256 b0, uint256 b1) internal pure returns (uint256 lo_, uint256 hi_) {
        assembly {
            lo_ := sub(a0, b0)
            hi_ := sub(sub(a1, b1), lt(a0, b0))
        }
    }

    /**
     * @notice Calculate the product `a * b` of two 256-bit unsigned integers using the chinese remainder theorem.
     * @dev Credits Remco Bloemen (MIT license): https://2π.com/17/chinese-remainder-theorem/
     * and Solady (MIT license): https://github.com/Vectorized/solady/
     * @param a The first operand
     * @param b The second operand
     * @return lo_ The low limb of the result of `a * b`
     * @return hi_ The high limb of the result of `a * b`
     */
    function _mul256(uint256 a, uint256 b) internal pure returns (uint256 lo_, uint256 hi_) {
        assembly {
            lo_ := mul(a, b)
            let mm := mulmod(a, b, not(0))
            hi_ := sub(mm, add(lo_, lt(mm, lo_)))
        }
    }

    /**
     * @notice Calculate the division `floor(a / b)` of a 512-bit unsigned integer by an unsigned 256-bit integer.
     * @dev Credits Solady (MIT license): https://github.com/Vectorized/solady/
     * The caller must ensure that the result fits inside a uint256 and that the division is non-zero.
     * For performance reasons, the caller should ensure that the numerator high limb (hi) is non-zero.
     * @param a0 The low limb of the numerator
     * @param a1 The high limb of the  numerator
     * @param b The denominator as a 256-bit unsigned integer
     * @return res_ The division `floor(a / b)` of the operands as an unsigned 256-bit integer
     */
    function _div256(uint256 a0, uint256 a1, uint256 b) internal pure returns (uint256 res_) {
        uint256 r;
        assembly {
            // To make the division exact, we find out the remainder of the division of a by b
            r := mulmod(a1, not(0), b) // (a1 * uint256.max) % b
            r := addmod(r, a1, b) // (r + a1) % b
            r := addmod(r, a0, b) // (r + a0) % b

            // `t` is the least significant bit of `b`.
            // Always greater or equal to 1.
            let t := and(b, sub(0, b))
            // Divide `b` by `t`, which is a power of two.
            b := div(b, t)
            // Invert `b mod 2**256`
            // Now that `b` is an odd number, it has an inverse
            // modulo `2**256` such that `b * inv = 1 mod 2**256`.
            // Compute the inverse by starting with a seed that is
            // correct for four bits. That is, `b * inv = 1 mod 2**4`.
            let inv := xor(2, mul(3, b))
            // Now use Newton-Raphson iteration to improve the precision.
            // Thanks to Hensel's lifting lemma, this also works in modular
            // arithmetic, doubling the correct bits in each step.
            inv := mul(inv, sub(2, mul(b, inv))) // inverse mod 2**8
            inv := mul(inv, sub(2, mul(b, inv))) // inverse mod 2**16
            inv := mul(inv, sub(2, mul(b, inv))) // inverse mod 2**32
            inv := mul(inv, sub(2, mul(b, inv))) // inverse mod 2**64
            inv := mul(inv, sub(2, mul(b, inv))) // inverse mod 2**128
            res_ :=
                mul(
                    // Divide [a1 a0] by the factors of two.
                    // Shift in bits from `a1` into `a0`. For this we need
                    // to flip `t` such that it is `2**256 / t`.
                    or(mul(sub(a1, gt(r, a0)), add(div(sub(0, t), t), 1)), div(sub(a0, r), t)),
                    // inverse mod 2**256
                    mul(inv, sub(2, mul(b, inv)))
                )
        }
    }

    /**
     * @notice Compute the division of a 768-bit integer `a` by a 512-bit integer `b`, knowing the reciprocal of `b`
     * @dev Credits chfast (Apache 2.0 License): https://github.com/chfast/intx
     * @param a0 The LSB of the numerator
     * @param a1 The middle limb of the numerator
     * @param a2 The MSB of the numerator
     * @param b0 The low limb of the divisor
     * @param b1 The high limb of the divisor
     * @param v The reciprocal `v` as defined in `_reciprocal_2`
     * @return The quotient floor(a/b)
     */
    function _div_2(uint256 a0, uint256 a1, uint256 a2, uint256 b0, uint256 b1, uint256 v)
        internal
        pure
        returns (uint256)
    {
        (uint256 q0, uint256 q1) = _mul256(v, a2);
        (q0, q1) = _add(q0, q1, a1, a2);
        (uint256 t0, uint256 t1) = _mul256(b0, q1);
        uint256 r1;
        assembly {
            r1 := sub(a1, mul(q1, b1))
        }
        uint256 r0;
        (r0, r1) = _sub(a0, r1, t0, t1);
        (r0, r1) = _sub(r0, r1, b0, b1);
        assembly {
            q1 := add(q1, 1)
        }
        if (r1 >= q0) {
            assembly {
                q1 := sub(q1, 1)
            }
            (r0, r1) = _add(r0, r1, b0, b1);
        }
        if (r1 > b1 || (r1 == b1 && r0 >= b0)) {
            assembly {
                q1 := add(q1, 1)
            }
            // we don't care about the remainder
            // (r0, r1) = _sub(r0, r1, b0, b1);
        }
        return q1;
    }

    /**
     * @notice Compute the reciprocal `v = floor((2^512-1) / d) - 2^256`
     * @dev The input must be normalized (d >= 2^255)
     * @param d The input value
     * @return v_ The reciprocal of d
     */
    function _reciprocal(uint256 d) internal pure returns (uint256 v_) {
        if (d & 0x8000000000000000000000000000000000000000000000000000000000000000 == 0) {
            revert HugeIntDivisionFailed();
        }
        v_ = _div256(type(uint256).max, type(uint256).max - d, d);
    }

    /**
     * @notice Compute the reciprocal `v = floor((2^768-1) / d) - 2^256`, where d is a uint512 integer
     * @dev Credits chfast (Apache 2.0 License): https://github.com/chfast/intx
     * @param d0 LSB of the input
     * @param d1 MSB of the input
     * @return v_ The reciprocal of d
     */
    function _reciprocal_2(uint256 d0, uint256 d1) internal pure returns (uint256 v_) {
        v_ = _reciprocal(d1);
        uint256 p;
        assembly {
            p := mul(d1, v_)
            p := add(p, d0)
            if lt(p, d0) {
                // carry out
                v_ := sub(v_, 1)
                if iszero(lt(p, d1)) {
                    v_ := sub(v_, 1)
                    p := sub(p, d1)
                }
                p := sub(p, d1)
            }
        }
        (uint256 t0, uint256 t1) = _mul256(v_, d0);
        assembly {
            p := add(p, t1)
            if lt(p, t1) {
                // carry out
                v_ := sub(v_, 1)
                if and(iszero(lt(p, d1)), or(gt(p, d1), iszero(lt(t0, d0)))) {
                    // if (<p, t0> >= <d1, d0>)
                    v_ := sub(v_, 1)
                }
            }
        }
    }

    /**
     * @notice Count the number of consecutive zero bits, starting from the left
     * @param x An unsigned integer
     * @return n_ The number of zeroes starting from the most significant bit
     */
    function _clz(uint256 x) internal pure returns (uint256 n_) {
        if (x == 0) {
            return 256;
        }
        assembly {
            if iszero(and(x, 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000)) {
                n_ := add(n_, 128)
                x := shl(128, x)
            }
            if iszero(and(x, 0xffffffffffffffff000000000000000000000000000000000000000000000000)) {
                n_ := add(n_, 64)
                x := shl(64, x)
            }
            if iszero(and(x, 0xffffffff00000000000000000000000000000000000000000000000000000000)) {
                n_ := add(n_, 32)
                x := shl(32, x)
            }
            if iszero(and(x, 0xffff000000000000000000000000000000000000000000000000000000000000)) {
                n_ := add(n_, 16)
                x := shl(16, x)
            }
            if iszero(and(x, 0xff00000000000000000000000000000000000000000000000000000000000000)) {
                n_ := add(n_, 8)
                x := shl(8, x)
            }
            if iszero(and(x, 0xf000000000000000000000000000000000000000000000000000000000000000)) {
                n_ := add(n_, 4)
                x := shl(4, x)
            }
            if iszero(and(x, 0xc000000000000000000000000000000000000000000000000000000000000000)) {
                n_ := add(n_, 2)
                x := shl(2, x)
            }
            if iszero(and(x, 0x8000000000000000000000000000000000000000000000000000000000000000)) { n_ := add(n_, 1) }
        }
    }
}
