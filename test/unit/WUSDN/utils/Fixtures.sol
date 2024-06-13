// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { WusdnHandler } from "test/unit/WUSDN/utils/Handler.sol";

import { Wusdn } from "src/Usdn/Wusdn.sol";

/**
 * @title WusdnTokenFixture
 * @dev Utils for testing Wusdn.sol
 */
contract WusdnTokenFixture is UsdnTokenFixture {
    WusdnHandler public wusdn;
    uint256 public usdnDecimals;

    function setUp() public virtual override {
        super.setUp();

        wusdn = new WusdnHandler(usdn);
        usdnDecimals = usdn.decimals();

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.MINTER_ROLE(), address(wusdn));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(address(this), 100 ether);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
