// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @notice Check the various bits of a bitfield indicating which token should be used with permit2
library Permit2TokenBitfield {
    type Bitfield is uint8;

    /// @dev mask for the asset token
    uint8 constant ASSET_MASK = 2 ** 0;

    /// @dev mask for the SDEX token
    uint8 constant SDEX_MASK = 2 ** 1;

    /**
     * @notice Check if the bitfield indicates that the asset token should be used with permit2
     * @param bitfield The bitfield
     * @return use_ True if the asset token should be used with permit2
     */
    function useForAsset(Bitfield bitfield) internal pure returns (bool use_) {
        assembly {
            use_ := gt(and(bitfield, ASSET_MASK), 0)
        }
    }

    /**
     * @notice Check if the bitfield indicates that the SDEX token should be used with permit2
     * @param bitfield The bitfield
     * @return use_ True if the SDEX token should be used with permit2
     */
    function useForSdex(Bitfield bitfield) internal pure returns (bool use_) {
        assembly {
            use_ := gt(and(bitfield, SDEX_MASK), 0)
        }
    }
}
