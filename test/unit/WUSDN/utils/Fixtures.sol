// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { WusdnHandler } from "test/unit/WUSDN/utils/Handler.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @title WusdnTokenFixture
 * @dev Utils for testing Wusdn.sol
 */
contract WusdnTokenFixture is UsdnTokenFixture {
    /// Events coming from the OpenZeppelin ERC4626
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    WusdnHandler public wusdn;

    function setUp() public virtual override {
        super.setUp();

        wusdn = new WusdnHandler(usdn);

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.MINTER_ROLE(), address(wusdn));
        usdn.mint(address(this), 100 ether);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
