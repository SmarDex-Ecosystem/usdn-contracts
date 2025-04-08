// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { PropertiesBase } from "./PropertiesBase.sol";

abstract contract Properties_ADMIN is PropertiesBase {
    function Invariant_ADMIN_01(bool shouldBeTrue) internal pure {
        assert(shouldBeTrue);
    }
}
