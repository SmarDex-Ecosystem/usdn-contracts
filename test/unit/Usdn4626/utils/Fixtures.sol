// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Usdn4626Handler } from "./Handler.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { Wusdn } from "../../../../src/Usdn/Wusdn.sol";

contract Usdn4626Fixture is Test {
    Usdn usdn = Usdn(0xde17a000BA631c5d7c2Bd9FB692EFeA52D90DEE2);
    Usdn4626Handler usdn4626;

    function setUp() public virtual {
        deployCodeTo("Usdn.sol", abi.encode(address(this), address(this)), 0xde17a000BA631c5d7c2Bd9FB692EFeA52D90DEE2);
        usdn4626 = new Usdn4626Handler();
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdn4626));
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdn4626));
    }
}
