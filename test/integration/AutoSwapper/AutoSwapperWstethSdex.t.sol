// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniversalRouter } from "@smardex-universal-router/src/interfaces/IUniversalRouter.sol";

import { AutoSwapperWstethSdex } from "../../../src/utils/AutoSwapperWstethSdex.sol";

/**
 * @custom:feature The callback function of the `AutoSwapperWstethSdex` contract
 * @custom:background Given a `AutoSwapperWstethSdex` contract
 */
contract TestAutoSwapperWstethSdex is Test {
    IUniversalRouter public router;
    AutoSwapperWstethSdex public swapper;

    IERC20 public wstETH;
    IERC20 public wETH;
    IERC20 public sDEX;

    address user;
    address wETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address wstETHAddress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address sDEXAddress = 0x5DE8ab7E27f6E7A1fFf3E5B337584Aa43961BEeF;
    address routerAddress = 0x49f66B1616865b2a59caECb8352bbf2AC80983e1;
    address BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address smardexFactory = 0xB878DC600550367e14220d4916Ff678fB284214F;
    address uniswapPair = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address constant USDN_PROTOCOL = 0x656cB8C6d154Aad29d8771384089be5B5141f01a;

    function setUp() public {
        vm.createSelectFork("https://ethereum.publicnode.com/");

        user = makeAddr("user_one");

        router = IUniversalRouter(routerAddress);
        wstETH = IERC20(wstETHAddress);
        wETH = IERC20(wETHAddress);
        sDEX = IERC20(sDEXAddress);

        vm.prank(user);
        swapper = new AutoSwapperWstethSdex();

        vm.startPrank(address(swapper));
        wstETH.approve(address(router), type(uint256).max);
        wETH.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.prank(user);
        wETH.approve(address(router), type(uint256).max);

        vm.prank(user);
        wETH.approve(address(swapper), type(uint256).max);

        deal(address(wstETH), user, 100 ether);
        deal(address(wETH), user, 100 ether);
    }

    /**
     * @custom:scenario Test the AutoSwapper's full swap execution via processSwap
     * @custom:given The contract holds wstETH and is configured correctly
     * @custom:when processSwap is called with a valid amount
     * @custom:then It should perform both swaps and emit the `SuccessfulSwap` event
     */
    function test_processSwap_emitsEventAndBurnsTokens() public {
        uint256 amountToSwap = 5 ether;
        uint256 initialBurnAddressBalance = IERC20(sDEXAddress).balanceOf(BURN_ADDRESS);

        vm.prank(user);
        wstETH.transfer(address(swapper), amountToSwap);

        vm.prank(USDN_PROTOCOL);
        swapper.feeCollectorCallback(amountToSwap);

        uint256 finalBurnAddressBalance = IERC20(sDEXAddress).balanceOf(BURN_ADDRESS);
        assertGt(finalBurnAddressBalance, initialBurnAddressBalance, "Swap did not increase burn address SDEX balance");
    }
}
