// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import { BaseFixture } from "test/utils/Fixtures.sol";

import { Contract } from "src/Contract.sol";

/**
 * @title ContractFixture
 * @dev Fixture for testing `Contract.sol`.
 * @dev Inherits from `BaseFixture` which defines useful labels for addresses shown in debugging traces.
 */
contract ContractFixture is BaseFixture {
    Contract c;

    function setUp() public virtual {
        c = new Contract();
    }
}

/**
 * @title TestContractBar
 * @dev Skeleton example for a test suite related to the `bar` function of `Contract.sol`.
 * A setup fixture is defined in `Fixtures.sol`. It's best to create more small contracts for tests.
 */
contract TestContractBar is ContractFixture {
    function setUp() public override {
        super.setUp();
    }

    function testBar() public {
        assertEq(uint256(1), uint256(1), "ok");
    }
}

/**
 * @title TestContractFoo
 * @dev Skeleton example for a test suite related to the `bar` function of `Contract.sol`.
 * A setup fixture is defined in `Fixtures.sol`. It's best to create more small contracts for tests.
 */
contract TestContractFoo is ContractFixture {
    function setUp() public override {
        super.setUp();
    }

    function testFoo(uint256 x) public {
        vm.assume(x < type(uint128).max);
        assertEq(x + x, x * 2);
    }
}
