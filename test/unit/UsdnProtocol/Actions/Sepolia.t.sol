// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

contract TestUsdnProtocolSepolia is UsdnProtocolBaseFixture {
    address constant SWEEP_ADMIN = 0xFB8A0f060CA1DB2f1D241a3b147aCDA1859901B0;

    function setUp() public {
        sepolia = true;
        super._setUp(DEFAULT_PARAMS);
        vm.deal(address(protocol), 1 ether);
    }

    function test_sweep() public {
        uint256 protocolBalance = wstETH.balanceOf(address(protocol));
        uint256 adminBalance = wstETH.balanceOf(address(this));
        bytes memory data = abi.encodeWithSignature("sweep_6874531(address,address)", address(wstETH), address(this));
        vm.prank(SWEEP_ADMIN);
        (bool success,) = address(protocol).call(data);
        require(success, "call failed");
        assertEq(wstETH.balanceOf(address(this)), protocolBalance + adminBalance);
    }

    function test_drain() public {
        uint256 protocolBalance = address(protocol).balance;
        uint256 adminBalance = address(this).balance;
        bytes memory data = abi.encodeWithSignature("drain_871564575(address)", address(this));
        vm.prank(SWEEP_ADMIN);
        (bool success,) = address(protocol).call(data);
        require(success, "call failed");
        assertEq(address(this).balance, protocolBalance + adminBalance);
    }

    function test_RevertWhen_unauthorized() public {
        bytes memory data = abi.encodeWithSignature("sweep_6874531(address,address)", address(wstETH), address(this));
        (bool success,) = address(protocol).call(data);
        assertFalse(success);

        data = abi.encodeWithSignature("drain_871564575(address)", address(this));
        (success,) = address(protocol).call(data);
        assertFalse(success);
    }

    receive() external payable { }
}
