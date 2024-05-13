// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { RouterParameters } from "src/UniversalRouter/base/RouterImmutables.sol";

import { DEPLOYER, WETH } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UniversalRouterHandler } from "test/unit/UniversalRouter/utils/Handler.sol";

/**
 * @title UniversalRouterBaseFixture
 * @dev Utils for testing the Universal Router
 */
contract UniversalRouterBaseFixture is BaseFixture {
    UniversalRouterHandler public router;
    RouterParameters public EMPTY_PARAMS;

    function _setUp(RouterParameters memory params) internal {
        vm.prank(DEPLOYER);
        router = new UniversalRouterHandler(params);
    }

    /// @dev TODO to use for integration tests
    function _forkMainnet() internal {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        RouterParameters memory params;
        params.permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        params.weth9 = WETH;
        params.v2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        params.v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        params.pairInitCodeHash = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f; // v2 pair hash
        params.poolInitCodeHash = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54; // v3 pool hash

        _setUp(params);
    }
}
