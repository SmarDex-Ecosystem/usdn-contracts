// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

contract TestUsdnProtocolDeposit is UsdnProtocolBaseFixture {
    function setUp() public override {
        super.setUp();
        wstETH.mint(address(this), 10 ether);
        wstETH.approve(address(protocol), type(uint256).max);
    }

    function test_deposit() public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        protocol.initiateDeposit(1 ether, currentPrice, hex"");
        // TODO: work in progress
    }
}
