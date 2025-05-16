// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SDEX as SDEX_ADDR } from "../../utils/Constants.sol";

import { IAutoSwapperWusdnSdex } from "../../../src/interfaces/Utils/IAutoSwapperWusdnSdex.sol";
import { AutoSwapperWusdnSdex } from "../../../src/utils/AutoSwapperWusdnSdex.sol";

/**
 * @custom:feature The `AutoSwapperWusdnSdex` contract
 * @custom:background Given a `AutoSwapperWusdnSdex` contract and a forked mainnet
 */
contract TestForkAutoSwapperWusdnSdex is Test {
    AutoSwapperWusdnSdex public autoSwapper;
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    IERC20 constant WUSDN = IERC20(0x99999999999999Cc837C997B882957daFdCb1Af9);
    IERC20 constant SDEX = IERC20(SDEX_ADDR);
    uint256 constant AMOUNT_TO_SWAP = 2000 ether;

    function setUp() public {
        vm.createSelectFork("mainnet");

        autoSwapper = new AutoSwapperWusdnSdex();

        deal(address(WUSDN), address(this), AMOUNT_TO_SWAP);
    }

    /**
     * @custom:scenario Test the AutoSwapper's swap execution via the callback function
     * @custom:when `feeCollectorCallback` is called
     * @custom:then It should perform the swap
     * @custom:and the SDEX balance of the burn address should increase
     * @custom:and the WUSDN and SDEX balances of the contract should be zero
     */
    function test_ForkFeeCollectorCallback() public {
        uint256 initialBurnAddressBalance = SDEX.balanceOf(BURN_ADDRESS);

        WUSDN.transfer(address(autoSwapper), AMOUNT_TO_SWAP);
        autoSwapper.feeCollectorCallback(1);

        assertEq(WUSDN.balanceOf(address(autoSwapper)), 0, "WUSDN balance not zero");
        assertEq(SDEX.balanceOf(address(autoSwapper)), 0, "SDEX balance not zero");
        assertGt(
            SDEX.balanceOf(BURN_ADDRESS), initialBurnAddressBalance, "Swap did not increase burn address SDEX balance"
        );
    }

    /**
     * @custom:scenario Test the `Ownable` access control of the AutoSwapper
     * @custom:when the `sweep` and `updateSwapSlippage` functions are called
     * @custom:then It should revert with the `OwnableUnauthorizedAccount` error
     */
    function test_ForkAdmin() public {
        address user = vm.addr(1);
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        autoSwapper.sweep(address(0), address(0), 1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        autoSwapper.updateSwapSlippage(1);

        vm.stopPrank();
    }

    /**
     * @custom:scenario Test the external function calls of the AutoSwapper
     * @custom:when the `smardexSwapCallback` function is called
     * @custom:then it should revert with the `AutoSwapperInvalidCaller` error
     */
    function test_ForkInvalidCaller() public {
        address user = vm.addr(1);
        vm.startPrank(user);

        vm.expectRevert(IAutoSwapperWusdnSdex.AutoSwapperInvalidCaller.selector);
        autoSwapper.smardexSwapCallback(1, 1, "");

        vm.stopPrank();
    }
}
