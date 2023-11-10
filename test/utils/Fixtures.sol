// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "./Constants.sol";

/**
 * @title BaseFixture
 * @dev Define labels for various accounts and contracts.
 */
contract BaseFixture is Test {
    constructor() {
        /* -------------------------------------------------------------------------- */
        /*                                  Accounts                                  */
        /* -------------------------------------------------------------------------- */
        vm.label(DEPLOYER, "Deployer");
        vm.label(ADMIN, "Admin");
        vm.label(USER_1, "User1");
        vm.label(USER_2, "User2");
        vm.label(USER_3, "User3");
        vm.label(USER_4, "User4");

        /* -------------------------------------------------------------------------- */
        /*                              Ethereum mainnet                              */
        /* -------------------------------------------------------------------------- */
        vm.label(USDC, "USDC");
        vm.label(USDT, "USDT");
        vm.label(WETH, "WETH");
        vm.label(SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                               Polygon mainnet                              */
        /* -------------------------------------------------------------------------- */
        vm.label(POLYGON_WMATIC, "WMATIC");
        vm.label(POLYGON_USDC, "USDC");
        vm.label(POLYGON_USDT, "USDT");
        vm.label(POLYGON_WETH, "WETH");
        vm.label(POLYGON_SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                              BNB chain mainnet                             */
        /* -------------------------------------------------------------------------- */
        vm.label(BSC_WBNB, "WBNB");
        vm.label(BSC_USDC, "USDC");
        vm.label(BSC_USDT, "USDT");
        vm.label(BSC_WETH, "WETH");
        vm.label(BSC_SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                              Arbitrum mainnet                              */
        /* -------------------------------------------------------------------------- */
        vm.label(ARBITRUM_USDC, "USDC");
        vm.label(ARBITRUM_USDT, "USDT");
        vm.label(ARBITRUM_WETH, "WETH");
        vm.label(ARBITRUM_SDEX, "SDEX");

        /* -------------------------------------------------------------------------- */
        /*                                Base mainnet                                */
        /* -------------------------------------------------------------------------- */
        vm.label(BASE_USDC, "USDC");
        vm.label(BASE_USDBC, "USDbC");
        vm.label(BASE_WETH, "WETH");
        vm.label(BASE_SDEX, "SDEX");
    }
}

/**
 * @title TickMathFixture
 * @dev Utils for testing TickMath.sol
 */
contract TickMathFixture is BaseFixture {
    function bound_int24(int24 x, int24 min, int24 max) internal pure returns (int24) {
        uint256 _x = uint256(int256(x) + type(int24).max);
        uint256 _min = uint256(int256(min) + type(int24).max);
        uint256 _max = uint256(int256(max) + type(int24).max);
        uint256 _bound = _bound(_x, _min, _max);
        return int24(int256(_bound) - int256(type(int24).max));
    }
}
