// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

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
        usdn = new UsdnHandler();
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
