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
     * @notice Calculate the division `floor(a / b)` of a 512-bit unsigned integer by a unsigned 256-bit integer.
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
            return a.lsb / b;
        }
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
        console2.log("remainder", r);
    }
}
