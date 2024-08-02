// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @title HugeUintHandler
 * @dev Wrapper to get gas usage report and coverage report
 */
contract HugeUintHandler {
    function wrap(uint256 x) external pure returns (HugeUint.Uint512 memory) {
        return HugeUint.wrap(x);
    }

    function add(HugeUint.Uint512 memory a, HugeUint.Uint512 memory b)
        external
        pure
        returns (HugeUint.Uint512 memory)
    {
        return HugeUint.add(a, b);
    }

    function sub(HugeUint.Uint512 memory a, HugeUint.Uint512 memory b)
        external
        pure
        returns (HugeUint.Uint512 memory)
    {
        return HugeUint.sub(a, b);
    }

    function mul(uint256 a, uint256 b) external pure returns (HugeUint.Uint512 memory) {
        return HugeUint.mul(a, b);
    }

    function mul(HugeUint.Uint512 memory a, uint256 b) external pure returns (HugeUint.Uint512 memory) {
        return HugeUint.mul(a, b);
    }

    function div(HugeUint.Uint512 memory a, uint256 b) external pure returns (uint256) {
        return HugeUint.div(a, b);
    }

    function div(HugeUint.Uint512 memory a, HugeUint.Uint512 memory b) external pure returns (uint256) {
        return HugeUint.div(a, b);
    }
}
