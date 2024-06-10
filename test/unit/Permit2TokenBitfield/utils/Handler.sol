// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Permit2TokenBitfield } from "src/libraries/Permit2TokenBitfield.sol";

/**
 * @title Permit2TokenBitfieldHandler
 * @dev Wrapper to get gas usage report and coverage report
 */
contract Permit2TokenBitfieldHandler {
    function useForAsset(Permit2TokenBitfield.Bitfield bitfield) external pure returns (bool) {
        return Permit2TokenBitfield.useForAsset(bitfield);
    }

    function useForUsdn(Permit2TokenBitfield.Bitfield bitfield) external pure returns (bool) {
        return Permit2TokenBitfield.useForUsdn(bitfield);
    }

    function useForSdex(Permit2TokenBitfield.Bitfield bitfield) external pure returns (bool) {
        return Permit2TokenBitfield.useForSdex(bitfield);
    }
}
