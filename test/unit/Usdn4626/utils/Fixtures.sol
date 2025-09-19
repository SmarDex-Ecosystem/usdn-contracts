// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Usdn4626Handler } from "./Handler.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";

contract Usdn4626Fixture is Test {
    Usdn usdn;
    Usdn4626Handler usdn4626;

    function setUp() public virtual {
        usdn = new Usdn(address(this), address(this));
        usdn4626 = new Usdn4626Handler(usdn);
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdn4626));
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdn4626));
    }
}
