// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

library Permit2TokenBitfield {
    type Bitfield is uint8;

    uint8 constant ASSET_MASK = 2 ** 0;
    uint8 constant USDN_MASK = 2 ** 1;
    uint8 constant SDEX_MASK = 2 ** 2;

    function useForAsset(Bitfield bitfield) internal pure returns (bool use_) {
        assembly {
            use_ := gt(and(bitfield, ASSET_MASK), 0)
        }
    }

    function useForUsdn(Bitfield bitfield) internal pure returns (bool use_) {
        assembly {
            use_ := gt(and(bitfield, USDN_MASK), 0)
        }
    }

    function useForSdex(Bitfield bitfield) internal pure returns (bool use_) {
        assembly {
            use_ := gt(and(bitfield, SDEX_MASK), 0)
        }
    }
}
