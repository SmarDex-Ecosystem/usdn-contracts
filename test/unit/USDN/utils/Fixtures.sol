// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2, USER_3, USER_4 } from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { IEventsErrors } from "../../../utils/IEventsErrors.sol";
import { UsdnHandler } from "./Handler.sol";

import { IUsdnErrors } from "../../../../src/interfaces/Usdn/IUsdnErrors.sol";
import { IUsdnEvents } from "../../../../src/interfaces/Usdn/IUsdnEvents.sol";

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
}
