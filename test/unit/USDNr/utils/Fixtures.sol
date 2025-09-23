// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Usdnr } from "../../../../src/Usdn/Usdnr.sol";

/// @dev Utils for testing USDNr token
contract UsdnrTokenFixture is BaseFixture {
    Usdnr public usdnr;
    Usdn public usdn;

    /// @dev The owner of USDNr, the minter and the rebaser role of USDN are assigned to this address
    function setUp() public virtual {
        usdn = new Usdn(address(this), address(this));
        usdnr = new Usdnr(usdn, address(this));
    }
}
