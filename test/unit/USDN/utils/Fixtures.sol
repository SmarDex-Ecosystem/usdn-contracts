// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnHandler } from "test/unit/USDN/utils/Handler.sol";
import { IEvents } from "test/utils/IEvents.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";
import { IUsdnErrors } from "src/interfaces/Usdn/IUsdnErrors.sol";

/**
 * @title UsdnTokenFixture
 * @dev Utils for testing Usdn.sol
 */
contract UsdnTokenFixture is BaseFixture, IEvents, IUsdnEvents, IUsdnErrors {
    UsdnHandler public usdn;

    function setUp() public virtual {
        usdn = new UsdnHandler();
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
