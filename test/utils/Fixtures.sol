// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";

import "test/utils/Constants.sol" as constants;

/**
 * @title BaseFixture
 * @dev Define labels for various accounts and contracts.
 */
contract BaseFixture is Test {
    modifier ethMainnetFork() {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        _;
    }

    constructor() {
        /* -------------------------------------------------------------------------- */
        /*                                  Accounts                                  */
        /* -------------------------------------------------------------------------- */
        vm.label(constants.DEPLOYER, "Deployer");
        vm.label(constants.ADMIN, "Admin");
        vm.label(constants.USER_1, "User1");
        vm.label(constants.USER_2, "User2");
        vm.label(constants.USER_3, "User3");
        vm.label(constants.USER_4, "User4");
        // deal ether
        vm.deal(constants.DEPLOYER, 10_000 ether);
        vm.deal(constants.ADMIN, 10_000 ether);
        vm.deal(constants.USER_1, 10_000 ether);
        vm.deal(constants.USER_2, 10_000 ether);
        vm.deal(constants.USER_3, 10_000 ether);
        vm.deal(constants.USER_4, 10_000 ether);

        /* -------------------------------------------------------------------------- */
        /*                              Ethereum mainnet                              */
        /* -------------------------------------------------------------------------- */
        vm.label(constants.USDC, "USDC");
        vm.label(constants.USDT, "USDT");
        vm.label(constants.WETH, "WETH");
        vm.label(constants.SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                               Polygon mainnet                              */
        /* -------------------------------------------------------------------------- */
        vm.label(constants.POLYGON_WMATIC, "WMATIC");
        vm.label(constants.POLYGON_USDC, "USDC");
        vm.label(constants.POLYGON_USDT, "USDT");
        vm.label(constants.POLYGON_WETH, "WETH");
        vm.label(constants.POLYGON_SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                              BNB chain mainnet                             */
        /* -------------------------------------------------------------------------- */
        vm.label(constants.BSC_WBNB, "WBNB");
        vm.label(constants.BSC_USDC, "USDC");
        vm.label(constants.BSC_USDT, "USDT");
        vm.label(constants.BSC_WETH, "WETH");
        vm.label(constants.BSC_SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                              Arbitrum mainnet                              */
        /* -------------------------------------------------------------------------- */
        vm.label(constants.ARBITRUM_USDC, "USDC");
        vm.label(constants.ARBITRUM_USDT, "USDT");
        vm.label(constants.ARBITRUM_WETH, "WETH");
        vm.label(constants.ARBITRUM_SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                                Base mainnet                                */
        /* -------------------------------------------------------------------------- */
        vm.label(constants.BASE_USDC, "USDC");
        vm.label(constants.BASE_USDBC, "USDbC");
        vm.label(constants.BASE_WETH, "WETH");
        vm.label(constants.BASE_SDEX, "SDEX");
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual { }
}
