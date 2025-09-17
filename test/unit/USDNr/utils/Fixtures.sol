// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Usdnr } from "../../../../src/Usdn/Usdnr.sol";

/**
 * @title UsdnrTokenFixture
 * @dev Utils for testing USDNr token
 */
contract UsdnrTokenFixture is BaseFixture {
    Usdnr public usdnr;
    Usdn public usdn;

    function setUp() public virtual {
        usdn = new Usdn(address(this), address(this));
        usdnr = new Usdnr(usdn);
    }
}
