// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";

import { Wusdn } from "src/Wusdn.sol";

/**
 * @title WusdnTokenFixture
 * @dev Utils for testing Wusdn.sol
 */
contract WusdnTokenFixture is UsdnTokenFixture {
    /// Events coming from the OpenZeppelin ERC4626
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    Wusdn wusdn;
    uint256 oneUSDN;

    function setUp() public virtual override {
        super.setUp();

        wusdn = new Wusdn(usdn);
        uint256 decimals = usdn.decimals();
        oneUSDN = 1 * 10 ** decimals;

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(address(this), 100 ether);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
