// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnHandler } from "test/unit/USDN/utils/Handler.sol";
import { IEvents } from "test/utils/IEvents.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";
import { IUsdnErrors } from "src/interfaces/Usdn/IUsdnErrors.sol";

/**
 * @title UsdnTokenFixture
 * @dev Utils for testing Usdn.sol
 */
contract UsdnTokenFixture is BaseFixture, IEvents, IUsdnEvents, IUsdnErrors {
    /// Events coming from the ERC20Permit extension
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    UsdnHandler public usdn;

    function setUp() public virtual {
        address[] memory _actors = new address[](4);
        _actors[0] = USER_1;
        _actors[1] = USER_2;
        _actors[2] = USER_3;
        _actors[3] = USER_4;
        usdn = new UsdnHandler(_actors);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
