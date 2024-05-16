// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

import { UniversalRouterBaseIntegrationFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { WETH, SDEX, WSTETH, PYTH_STETH_USD } from "test/utils/Constants.sol";

/**
 * @custom:feature Test commands lower than first boundary of the `execute` function
 * @custom:background A initiated universal router
 */
contract TestExecuteFourthBoundary is UniversalRouterBaseIntegrationFixture {
    uint256 constant BASE_AMOUNT = 10_000;

    function setUp() external {
        _setUp();

        deal(WETH, address(this), BASE_AMOUNT * 1e3);
        deal(address(sdex), address(this), BASE_AMOUNT * 1e3);
        deal(address(wstETH), address(this), BASE_AMOUNT * 1e3);

        // mint usdn
        sdex.approve(address(protocol), type(uint256).max);
        wstETH.approve(address(protocol), type(uint256).max);

        uint256 messageValue =
            oracleMiddleware.validationCost("", ProtocolAction.InitiateDeposit) + protocol.getSecurityDepositValue();

        // protocol.initiateDeposit{ value: messageValue }(
        //     uint128(BASE_AMOUNT), priceData, EMPTY_PREVIOUS_DATA, address(this)
        // );

        // _waitDelay();

        // protocol.validateDeposit(abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);
    }

    // function test_test() external {
    //     // vm.skip(true);
    //     assertTrue(true);
    // }
}
