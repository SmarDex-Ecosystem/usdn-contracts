// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { HugeInt } from "src/libraries/HugeInt.sol";

/**
 * @title HugeIntHandler
 * @dev Wrapper to get gas usage report and coverage report
 */
contract HugeIntHandler {
    function wrap(uint256 x) external pure returns (HugeInt.Uint512 memory) {
        return HugeInt.wrap(x);
    }

    function add(HugeInt.Uint512 memory a, HugeInt.Uint512 memory b) external pure returns (HugeInt.Uint512 memory) {
        return HugeInt.add(a, b);
    }

    function sub(HugeInt.Uint512 memory a, HugeInt.Uint512 memory b) external pure returns (HugeInt.Uint512 memory) {
        return HugeInt.sub(a, b);
    }

    function mul(uint256 a, uint256 b) external pure returns (HugeInt.Uint512 memory) {
        return HugeInt.mul(a, b);
    }

    function div256(HugeInt.Uint512 memory a, uint256 b) external pure returns (uint256) {
        return HugeInt.div256(a, b);
    }

    function div(HugeInt.Uint512 memory a, HugeInt.Uint512 memory b) external pure returns (uint256) {
        return HugeInt.div(a, b);
    }

    function clz(uint256 x) external pure returns (uint256 n_) {
        n_ = HugeInt._clz(x);
    }
}
