// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnHandler } from "test/unit/USDN/utils/Handler.sol";
import { IEventsErrors } from "test/utils/IEventsErrors.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";
import { IUsdnErrors } from "src/interfaces/Usdn/IUsdnErrors.sol";

/**
 * @title UsdnTokenFixture
 * @dev Utils for testing Usdn.sol
 */
contract UsdnTokenFixture is BaseFixture, IEventsErrors, IUsdnEvents, IUsdnErrors {
    UsdnHandler public usdn;

    function setUp() public virtual {
        address[] memory _actors = new address[](4);
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;
        usdn = new UsdnHandler();
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
