// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnHandler } from "test/unit/USDN/utils/Handler.sol";

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

    /// Events coming from the ERC20Permit extension
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    UsdnHandler public usdn;

    function setUp() public virtual {
        usdn = new UsdnHandler();
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
