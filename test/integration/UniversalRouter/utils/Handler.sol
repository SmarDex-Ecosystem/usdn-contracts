// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { UniversalRouter } from "src/UniversalRouter/UniversalRouter.sol";
import { RouterParameters } from "src/UniversalRouter/base/RouterImmutables.sol";

/**
 * @title UniversalRouterHandler
 * @dev Wrapper to aid in testing the universal router
 */
contract UniversalRouterHandler is UniversalRouter, Test {
    constructor(RouterParameters memory params) UniversalRouter(params) { }
}
