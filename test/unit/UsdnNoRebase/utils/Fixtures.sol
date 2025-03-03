// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnNoRebase } from "../../../../src/Usdn/UsdnNoRebase.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { IEventsErrors } from "../../../utils/IEventsErrors.sol";

import { IUsdnErrors } from "../../../../src/interfaces/Usdn/IUsdnErrors.sol";
import { IUsdnEvents } from "../../../../src/interfaces/Usdn/IUsdnEvents.sol";

/**
 * @title UsdnTokenFixture
 * @dev Utils for testing Usdn.sol
 */
contract UsdnNoRebaseTokenFixture is BaseFixture, IEventsErrors, IUsdnEvents, IUsdnErrors {
    UsdnNoRebase public usdn;

    function setUp() public virtual {
        usdn = new UsdnNoRebase("NAME", "SYMBOL");
    }
}
