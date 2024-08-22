// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console2 } from "forge-std/Test.sol";

import { BaseFixture } from "../../../utils/Fixtures.sol";
import { TickMathHandler } from "../utils/Handler.sol";

/**
 * @title TickMathFixture
 * @dev Utils for testing TickMath.sol
 */
contract TickMathFixture is BaseFixture {
    TickMathHandler public handler; // wrapper to get gas usage report

    function setUp() public virtual {
        handler = new TickMathHandler();
    }

    /// Bounds an int24 value between min and max and prints the resulting value
    function bound_int24(int24 x, int24 min, int24 max) internal pure returns (int24 res_) {
        uint256 _x = uint256(int256(x) + type(int24).max);
        uint256 _min = uint256(int256(min) + type(int24).max);
        uint256 _max = uint256(int256(max) + type(int24).max);
        uint256 _bound = _bound(_x, _min, _max);
        res_ = int24(int256(_bound) - int256(type(int24).max));
        console2.log("Bound Result", res_);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
