// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { WusdnHandler } from "test/unit/WUSDN/utils/Handler.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";

import { Wusdn } from "src/Usdn/Wusdn.sol";
import { Usdn } from "src/Usdn/Usdn.sol";

/**
 * @title WusdnTokenFixture
 * @dev Utils for testing Wusdn.sol
 */
contract WusdnTokenFixture is BaseFixture {
    WusdnHandler public wusdn;
    uint256 public usdnDecimals;
    Usdn public usdn;

    function setUp() public virtual {
        address[] memory _actors = new address[](4);
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;
        usdn = new Usdn(address(0), address(0));

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
