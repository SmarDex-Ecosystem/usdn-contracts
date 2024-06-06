// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SmardexSwapRouter } from "src/UniversalRouter/modules/smardex/SmardexSwapRouter.sol";

import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";
import { WETH, SDEX } from "test/utils/Constants.sol";

/**
 * @custom:feature Test the universalRouter `smardexSwapCallback` function
 * @custom:background A initiated universal router
 */
contract TestForkSmardexSwapCallback is UniversalRouterBaseFixture {
    function setUp() external {
        _setUp();
    }

    /**
     * @custom:scenario Test the `smardexSwapCallback` with invalid amounts
     * @custom:given The initiated universal router
     * @custom:when The function is called
     * @custom:then The transaction should revert with `callbackInvalidAmount`
     */
    function test_RevertWhen_ForkCallbackInvalidAmount() external {
        vm.expectRevert(SmardexSwapRouter.callbackInvalidAmount.selector);
        router.smardexSwapCallback(0, 0, "");
    }

    /**
     * @custom:scenario Test the `smardexSwapCallback` with invalid amounts
     * @custom:given The initiated universal router
     * @custom:when The function is called
     * @custom:then The transaction should revert with `callbackInvalidAmount`
     */
    function test_RevertWhen_ForkInvalidPair() external {
        vm.expectRevert(SmardexSwapRouter.invalidPair.selector);
        router.smardexSwapCallback(
            1, 0, abi.encode(SmardexSwapRouter.SwapCallbackData(abi.encodePacked(WETH, SDEX), address(this)))
        );
    }
}
