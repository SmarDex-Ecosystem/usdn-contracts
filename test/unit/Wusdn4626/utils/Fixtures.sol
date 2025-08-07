// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Wusdn4626Handler } from "./Handler.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../../src/Usdn/Wusdn.sol";

contract Wusdn4626Fixture is Test {
    Usdn usdn;
    Wusdn wusdn;
    Wusdn4626Handler wusdn4626;

    function setUp() public virtual {
        usdn = new Usdn(address(this), address(this));
        wusdn = new Wusdn(usdn);
        vm.etch(0x99999999999999Cc837C997B882957daFdCb1Af9, address(wusdn).code);
        wusdn = Wusdn(0x99999999999999Cc837C997B882957daFdCb1Af9);
        wusdn4626 = new Wusdn4626Handler();

        usdn.grantRole(usdn.REBASER_ROLE(), address(wusdn4626));
    }
}
