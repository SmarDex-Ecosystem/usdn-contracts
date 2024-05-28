// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { DEPLOYER, WETH, WSTETH } from "test/utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "test/integration/UsdnProtocol/utils/Fixtures.sol";
import { UniversalRouterHandler } from "test/integration/UniversalRouter/utils/Handler.sol";
import { RouterParameters } from "src/UniversalRouter/base/RouterImmutables.sol";

/**
 * @title UniversalRouterBaseFixture
 * @dev Utils for testing the Universal Router
 */
contract UniversalRouterBaseFixture is UsdnProtocolBaseIntegrationFixture {
    UniversalRouterHandler public router;
    IAllowanceTransfer permit2;

    function _setUp() internal {
        params = DEFAULT_PARAMS;
        params.fork = true;
        _setUp(params);

        RouterParameters memory params = RouterParameters({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            weth9: WETH,
            v2Factory: 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
            v3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            pairInitCodeHash: 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f, // v2 pair hash
            poolInitCodeHash: 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54, // v3 pool hash
            usdnProtocol: protocol,
            wstEth: WSTETH
        });

        vm.prank(DEPLOYER);
        router = new UniversalRouterHandler(params);

        permit2 = IAllowanceTransfer(params.permit2);
    }
}
