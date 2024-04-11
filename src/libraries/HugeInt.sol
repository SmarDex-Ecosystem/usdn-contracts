// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";

library HugeInt {
    error HugeIntDivisionFailed();

    struct Uint512 {
        uint256 lsb;
        uint256 msb;
    }

    function wrap(uint256 x) internal pure returns (Uint512 memory) {
        return Uint512(x, 0);
    }

    /**
     * @notice Calculate the sum `a + b` of two 512-bit unsigned integers.
     * @dev Credits Remco Bloemen (MIT license): https://2π.com/17/512-bit-division/
     * The result is not checked for overflow, the caller must ensure that the result is less than 2^512.
     * @param a The first operand
     * @param b The second operand
     */
    function add(Uint512 memory a, Uint512 memory b) internal pure returns (Uint512 memory res_) {
        (uint256 a0, uint256 a1) = (a.lsb, a.msb);
        (uint256 b0, uint256 b1) = (b.lsb, b.msb);
        uint256 lsb;
        uint256 msb;
        assembly {
            lsb := add(a0, b0)
            msb := add(add(a1, b1), lt(lsb, a0))
        }
        return Uint512(lsb, msb);
    }

    /**
     * @notice Calculate the difference `a - b` of two 512-bit unsigned integers.
     * @dev Credits Remco Bloemen (MIT license): https://2π.com/17/512-bit-division/
     * The result is not checked for overflow, the caller must ensure that the second operand is less than or equal to
     * the first operand.
     * @param a The first operand
     * @param b The second operand
     */
    function sub(Uint512 memory a, Uint512 memory b) internal pure returns (Uint512 memory res_) {
        (uint256 a0, uint256 a1) = (a.lsb, a.msb);
        (uint256 b0, uint256 b1) = (b.lsb, b.msb);
        uint256 lsb;
        uint256 msb;
        assembly {
            lsb := sub(a0, b0)
            msb := sub(sub(a1, b1), lt(a0, b0))
        }
        return Uint512(lsb, msb);
    }

    /**
     * @notice Calculate the product `a * b` of two 256-bit unsigned integers using the chinese remainder theorem.
     * @dev Credits Remco Bloemen (MIT license): https://2π.com/17/chinese-remainder-theorem/
     * and Solady (MIT license): https://github.com/Vectorized/solady/
     * The result is not checked for overflow, the caller must ensure that the result is less than 2^512.
     * @param a The first operand
     * @param b The second operand
     * @return res_ The product `a * b` of the operands as an unsigned 512-bit integer
     */
    function mul(uint256 a, uint256 b) internal pure returns (Uint512 memory) {
        uint256 lsb;
        uint256 msb;
        assembly {
            lsb := mul(a, b)
            let mm := mulmod(a, b, not(0))
            msb := sub(mm, add(lsb, lt(mm, lsb)))
        }
        return Uint512(lsb, msb);
    }

    /**
     * @notice Calculate the division `floor(a / b)` of a 512-bit unsigned integer by an unsigned 256-bit integer.
     * @dev Credits Solady (MIT license): https://github.com/Vectorized/solady/
     * The call will revert if the result doesn't fit inside a uint256 or if the denominator is zero.
     * @param a The numerator as a 512-bit unsigned integer
     * @param b The denominator as a 256-bit unsigned integer
     * @return res_ The division `floor(a / b)` of the operands as an unsigned 256-bit integer
     */
    function div256(Uint512 memory a, uint256 b) internal pure returns (uint256 res_) {
        // make sure the output fits inside a uint256, also prevents b == 0
        if (b <= a.msb) {
            revert HugeIntDivisionFailed();
        }
        // if the numerator is smaller than the denominator, the result is zero
        if (a.msb == 0 && a.lsb < b) {
            return 0;
        }
        // the first operand fits in 256 bits, we can use the Solidity division operator
        if (a.msb == 0) {
            unchecked {
                return a.lsb / b;
            }
        }
        res_ = _div256(a, b);
    }

    /**
     * @notice Compute the division floor(a/b) of two 512-bit integers, knowing the result fits inside a uint256.
     * @dev Credits chfast (Apache 2.0 License): https://github.com/chfast/intx
     * @param a The numerator as a 512-bit integer
     * @param b The denominator as a 512-bit integer
     * @return res_ The quotient floor(a/b)
     */
    function div(Uint512 memory a, Uint512 memory b) internal pure returns (uint256 res_) {
        // prevents b == 0
        if (b.msb == 0 && b.lsb == 0) {
            revert HugeIntDivisionFailed();
        }
        // if both operands fit inside a uint256, we can use the Solidity division operator
        if (a.msb == 0 && b.msb == 0) {
            unchecked {
                return a.lsb / b.lsb;
            }
        }
        // if the numerator is smaller than the denominator, the result is zero
        if (a.msb < b.msb || (a.msb == b.msb && a.lsb < b.lsb)) {
            return 0;
        }
        // if the divisor and result fit inside a uint256, we can use the {div256} function
        if (b.msb == 0 && b.lsb > a.msb) {
            return _div256(a, b.lsb);
        }
        // Division algo
        (uint256 a0, uint256 a1) = (a.lsb, a.msb);
        (uint256 b0, uint256 b1) = (b.lsb, b.msb);

        uint256 lsh = _clz(b1);
        if (lsh == 0) {
            // numerator is equal or larger than the denominator, and denominator is at least 0b1000...
            // the result is necessarily 1
            return 1;
        }

        unchecked {
            uint256 rsh = 256 - lsh;

            uint256 bn_lo = b0 << lsh;
            uint256 bn_hi = (b1 << lsh) | (b0 >> rsh);

            uint256 v = _reciprocal_2(bn_lo, bn_hi);
            res_ = _div_2(a1 >> rsh, (a1 << lsh) | (a0 >> rsh), a0 << lsh, Uint512(bn_lo, bn_hi), v);
        }
    }

    /**
     * @notice Calculate the division `floor(a / b)` of a 512-bit unsigned integer by an unsigned 256-bit integer.
     * @dev The caller must ensure that the result fits inside a uint256 and that the division is non-zero.
     * The caller must ensure that the numerator high limb (msb) is non-zero.
     * @param a The numerator as a 512-bit unsigned integer
     * @param b The denominator as a 256-bit unsigned integer
     * @return res_ The division `floor(a / b)` of the operands as an unsigned 256-bit integer
     */
    function _div256(Uint512 memory a, uint256 b) internal pure returns (uint256 res_) {
        (uint256 a0, uint256 a1) = (a.lsb, a.msb);
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
     * @param a2 The MSB of the numerator
     * @param a1 The middle limb of the numerator
     * @param a0 The LSB of the numerator
     * @param b The divisor as a 512-bit integer
     * @param v The reciprocal `v = 1/b` as defined in `_reciprocal_2`
     * @return The quotient floor(a/b)
     */
    function _div_2(uint256 a2, uint256 a1, uint256 a0, Uint512 memory b, uint256 v) internal pure returns (uint256) {
        unchecked {
            Uint512 memory q = mul(v, a2);
            q = add(q, Uint512(a1, a2));
            uint256 r1 = a1 - q.msb * b.msb;
            Uint512 memory t = mul(b.lsb, q.msb);
            Uint512 memory r = sub(sub(Uint512(a0, r1), t), b);
            r1 = r.msb;
            q.msb++;
            if (r1 >= q.lsb) {
                q.msb--;
                r = add(r, b);
            }
            if (r1 > b.msb || (r1 == b.msb && r.lsb >= b.lsb)) {
                q.msb++;
                r = sub(r, b);
            }
            return q.msb;
        }
    }

    /**
     * @notice Compute the reciprocal v = 1/d with fixed decimals
     * @param d The input value
     * @return v_ The reciprocal of d
     */
    function _reciprocal(uint256 d) internal pure returns (uint256 v_) {
        v_ = _div256(Uint512(255, 255 - d), d);
    }

    /**
     * @notice Compute the reciprocal v = 1/d with fixed decimals, where d is a uint512 integer
     * @dev Credits chfast (Apache 2.0 License): https://github.com/chfast/intx
     * @param d0 LSB of the input
     * @param d1 MSB of the input
     * @return v_ The reciprocal of d
     */
    function _reciprocal_2(uint256 d0, uint256 d1) internal pure returns (uint256 v_) {
        unchecked {
            v_ = _reciprocal(d1);
            uint256 p = d1 * v_;
            p += d0;
            if (p < d0) {
                v_--;
                if (p >= d1) {
                    v_--;
                    p -= d1;
                }
                p -= d1;
            }
            Uint512 memory t = mul(v_, d0);
            p += t.msb;
            if (p < t.msb) {
                v_--;
                if (p >= d1) {
                    if (p > d1 || t.lsb >= d0) {
                        v_--;
                    }
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
