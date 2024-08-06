// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { FuzzActions } from "./functional/FuzzActions.sol";
import { FuzzSetup } from "./functional/FuzzSetup.sol";
import { ErrorsChecked } from "./helpers/ErrorsChecked.sol";

contract FuzzingSuite is FuzzActions, FuzzSetup {
    function _checkErrors(bytes memory err, bytes4[][] memory errorsArrays)
        internal
        virtual
        override(ErrorsChecked, FuzzSetup)
    {
        super._checkErrors(err, errorsArrays);
    }
}
