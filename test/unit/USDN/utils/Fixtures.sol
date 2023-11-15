// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";

import { Usdn } from "src/Usdn.sol";
import { IUsdnEvents, IUsdnErrors } from "src/interfaces/IUsdn.sol";

/**
 * @title UsdnTokenFixture
 * @dev Utils for testing Usdn.sol
 */
contract UsdnTokenFixture is BaseFixture, IUsdnEvents, IUsdnErrors {
    /// Events coming from the OpenZeppelin IERC20
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    Usdn public usdn;

    function setUp() public virtual {
        usdn = new Usdn(address(0), address(0));
    }
}
