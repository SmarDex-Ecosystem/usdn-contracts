// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { RebalancerFixture } from "./utils/Fixtures.sol";

import { IBaseRebalancer } from "../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancer } from "../../../src/interfaces/Rebalancer/IRebalancer.sol";
import { IOwnershipCallback } from "../../../src/interfaces/UsdnProtocol/IOwnershipCallback.sol";

/**
 * @custom:feature The {supportsInterface} function of the rebalancer contract
 * @custom:background Given a rebalancer contract
 */
contract TestRebalancerSupportsInterface is RebalancerFixture {
    function setUp() public {
        super._setUp();
    }

    /**
     * @custom:scenario Check that the rebalancer contract supports the correct interfaces
     * @custom:given A deployed rebalancer contract
     * @custom:when The {supportsInterface} function is called with the interface IDs
     * @custom:then The function should return `true` for the supported interfaces and `false` for any other interface
     */
    function test_supportsInterface() public view {
        assertEq(rebalancer.supportsInterface(type(IERC165).interfaceId), true, "IERC165_ID supported");
        assertEq(
            rebalancer.supportsInterface(type(IOwnershipCallback).interfaceId), true, "IOwnershipCallback_ID supported"
        );
        assertEq(rebalancer.supportsInterface(type(IRebalancer).interfaceId), true, "IRebalancer_ID supported");
        assertEq(rebalancer.supportsInterface(type(IBaseRebalancer).interfaceId), true, "IBaseRebalancer_ID supported");
        assertEq(rebalancer.supportsInterface(""), false, "unknown interface ID");
    }
}
