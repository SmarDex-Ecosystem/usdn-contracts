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
        dealAccounts();
        _;
    }

    modifier adminPrank() {
        vm.startPrank(constants.ADMIN);
        _;
        vm.stopPrank();
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
        dealAccounts();

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

    function dealAccounts() internal {
        // deal ether
        vm.deal(constants.DEPLOYER, 10_000 ether);
        vm.deal(constants.ADMIN, 10_000 ether);
        vm.deal(constants.USER_1, 10_000 ether);
        vm.deal(constants.USER_2, 10_000 ether);
        vm.deal(constants.USER_3, 10_000 ether);
        vm.deal(constants.USER_4, 10_000 ether);
    }

    /**
     * @notice Call the test_utils rust command via vm.ffi
     * @dev You need to use `cargo build --release` in the `test_utils` directory before executing your test
     * @param commandName The name of the command to call
     * @param parameter The parameter for the command
     */
    function vmFFIRustCommand(string memory commandName, string memory parameter) internal returns (bytes memory) {
        return vmFFIRustCommand(commandName, parameter, "", "", "");
    }

    /**
     * @notice Call the test_utils rust command via vm.ffi
     * @dev You need to use `cargo build --release` in the `test_utils` directory before executing your test
     * @param commandName The name of the command to call
     * @param parameter1 The first parameter for the command
     * @param parameter2 The second parameter for the command
     */
    function vmFFIRustCommand(string memory commandName, string memory parameter1, string memory parameter2)
        internal
        returns (bytes memory)
    {
        return vmFFIRustCommand(commandName, parameter1, parameter2, "", "");
    }

    /**
     * @notice Call the test_utils rust command via vm.ffi
     * @dev You need to use `cargo build --release` in the `test_utils` directory before executing your test
     * @param commandName The name of the command to call
     * @param parameter1 The first parameter for the command
     * @param parameter2 The second parameter for the command
     * @param parameter3 The third parameter for the command
     */
    function vmFFIRustCommand(
        string memory commandName,
        string memory parameter1,
        string memory parameter2,
        string memory parameter3
    ) internal returns (bytes memory) {
        return vmFFIRustCommand(commandName, parameter1, parameter2, parameter3, "");
    }

    /**
     * @notice Call the test_utils rust command via vm.ffi
     * @dev You need to use `cargo build --release` in the `test_utils` directory before executing your test
     * @param commandName The name of the command to call
     * @param parameter1 The first parameter for the command
     * @param parameter2 The second parameter for the command
     * @param parameter3 The third parameter for the command
     * @param parameter4 The fourth parameter for the command
     */
    function vmFFIRustCommand(
        string memory commandName,
        string memory parameter1,
        string memory parameter2,
        string memory parameter3,
        string memory parameter4
    ) internal returns (bytes memory result_) {
        string[] memory cmds = new string[](6);

        cmds[0] = "./test_utils/target/release/test_utils";
        cmds[1] = commandName;
        cmds[2] = parameter1;
        cmds[3] = parameter2;
        cmds[4] = parameter3;
        cmds[5] = parameter4;

        // As of now, the first 3 arguments are always used
        uint8 usedParametersCount = 3;
        if (bytes(parameter2).length > 0) ++usedParametersCount;
        if (bytes(parameter3).length > 0) ++usedParametersCount;

        result_ = _vmFFIRustCommand(cmds, usedParametersCount);
    }

    /**
     * @notice Execute the given command
     * @dev Will shrink the cmds array to a length of `argsCount`
     * @param cmds The different parts of the command to execute
     * @param argsCount The number of used parameters
     */
    function _vmFFIRustCommand(string[] memory cmds, uint8 argsCount) private returns (bytes memory) {
        assembly {
            // shrink the array to avoid passing too many arguments to the command
            mstore(cmds, argsCount)
        }

        return vm.ffi(cmds);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual { }
}
